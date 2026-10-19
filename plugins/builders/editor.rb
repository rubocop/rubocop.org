# frozen_string_literal: true

require 'language_server/protocol/transport/io/reader'
require 'language_server/protocol/transport/io/writer'
require 'open3'
require 'tempfile'

module Builders
  # Opens a file of the demo in RuboCop's language server the way an editor
  # does, for "In your editor": the diagnostics it publishes as you type,
  # with their quick fixes, then what's left once formatting on save has
  # applied its corrections.
  class Editor < SiteBuilder
    include Demo

    FILE = 'lib/greeter.rb'
    # The diagnostic shown opened up, with its quick fixes, before saving.
    # After saving it's the first one left.
    OPEN = 'Style/StringLiterals'
    # Seconds to wait for the server to say anything before giving up on it.
    PATIENCE = 30

    def build
      hook :site, :post_read do
        site.data[:editor] = cache.getset(demo_key(__FILE__)) { session }
      end
    end

    private

    def session
      in_demo_copy do |dir|
        Tempfile.create('lsp') { |log| serve(dir, log) }
      end
    end

    # A stuck server is killed rather than waited on, and what it logged
    # goes into the error.
    def serve(dir, log)
      Open3.popen2(*rubocop_command('--lsp'), chdir: dir, err: log) do |input, output, server|
        output.timeout = PATIENCE
        edit(Client.new(input, output), dir)
      rescue IO::TimeoutError, Client::Error => e
        Process.kill('KILL', server.pid) if server.alive?
        raise e.class, "#{e.message}\nThe server logged:\n#{File.read(log.path)}"
      end
    end

    # Opens the file, formats it the way saving does, and takes the
    # diagnostics before and after.
    def edit(client, dir)
      document = { uri: "file://#{File.join(dir, FILE)}" }
      source = File.read(demo_path(FILE))
      client.request('initialize', processId: nil, rootUri: "file://#{dir}", capabilities: {})
      client.notify('initialized')
      client.notify('textDocument/didOpen', textDocument: { **document, languageId: 'ruby', version: 1, text: source })
      typing = state(source, client.diagnostics) { |diagnostic| diagnostic[:cop] == OPEN }
      saved = save(client, document, source)
      { file: FILE, typing:, saved: state(saved, client.diagnostics) { true } }.tap { client.request('shutdown') }
    end

    # RuboCop answers formatting with one edit that replaces the whole file,
    # or none when there's nothing to correct.
    def save(client, document, source)
      options = { tabSize: 2, insertSpaces: true }
      edits = client.request('textDocument/formatting', textDocument: document, options:)
      raise Client::Error, "expected an edit for the whole file, got #{edits.size}" if edits.size > 1

      (edits.empty? ? source : edits.first[:newText]).tap do |saved|
        changes = [{ text: saved }]
        client.notify('textDocument/didChange', textDocument: { **document, version: 2 }, contentChanges: changes)
      end
    end

    # The text a line at a time, cut into the stretches the diagnostics
    # underline and the ones between them, and the diagnostic opened up under
    # its line.
    def state(text, diagnostics, &)
      lines = text.lines(chomp: true)
      diagnostics = diagnostics.map { |diagnostic| summarize(diagnostic, lines) }
      open = diagnostics.find(&)
      lines.each_with_index.map do |line, i|
        here = diagnostics.select { |diagnostic| diagnostic[:line] == i }
        { segments: segments(line, here), open: (open if here.include?(open)) }
      end
    end

    # Where a diagnostic is underlined: on its first line, to the end of it
    # if it goes on past it.
    def summarize(diagnostic, lines)
      start, finish = diagnostic[:range].values_at(:start, :end)
      line = start[:line]
      {
        cop: diagnostic[:code], severity: diagnostic[:severity], message: diagnostic[:message].strip,
        line:, from: start[:character], to: finish[:line] == line ? finish[:character] : lines[line].size,
        fixes: diagnostic.dig(:data, :code_actions).to_a.map { |action| action[:title] }
      }
    end

    # Text with the diagnostic underlining it, or nil. A diagnostic that
    # overlaps one before it is left out.
    def segments(line, diagnostics)
      done = 0
      underlined = diagnostics.sort_by { |diagnostic| diagnostic[:from] }.flat_map do |diagnostic|
        from, to = diagnostic.values_at(:from, :to)
        next [] if from < done

        [[line[done...from], nil], [line[from...to], diagnostic]].tap { done = to }
      end
      underlined + [[line[done..].to_s, nil]]
    end

    # Just enough of a language client: requests, notifications, and waiting
    # for an answer or a notification while skipping everything else.
    class Client
      class Error < StandardError; end

      def initialize(input, output)
        @writer = LanguageServer::Protocol::Transport::Io::Writer.new(input)
        @reader = LanguageServer::Protocol::Transport::Io::Reader.new(output)
        @id = 0
      end

      def request(method, **params)
        id = (@id += 1)
        @writer.write(id:, method:, params:)
        message = read_until { |candidate| candidate[:id] == id }
        raise Error, "the language server answered #{method} with #{message[:error]}" if message[:error]

        message[:result]
      end

      def notify(method, **params)
        @writer.write(method:, params:)
      end

      # The diagnostics the server publishes next.
      def diagnostics
        read_until { |message| message[:method] == 'textDocument/publishDiagnostics' }.dig(:params, :diagnostics)
      end

      private

      def read_until
        @reader.read { |message| return message if yield(message) }
        raise Error, 'the language server hung up'
      end
    end
  end
end
