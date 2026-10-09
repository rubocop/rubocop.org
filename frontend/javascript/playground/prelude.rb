# frozen_string_literal: true

# Loaded once, when the playground's worker boots ruby.wasm, right after
# plugins/rubocop_html.rb and from /work. Everything the page sends arrives as
# plain files in /pg, so user input never ends up inside Ruby code.

# ruby.wasm has no sockets, and RuboCop only needs the constants to exist.
unless defined?(Socket)
  class SocketError < StandardError; end
  class BasicSocket < IO; end
  class IPSocket < BasicSocket; end
  class TCPSocket < IPSocket; end
  class UDPSocket < IPSocket; end

  # A stand-in that fails loudly if anything tries to connect.
  class Socket < BasicSocket
    # Empty, but some code checks that it's there.
    module Constants; end

    AF_INET = 2
    AF_INET6 = 10

    def self.tcp(*) = raise(NotImplementedError)
    def self.getaddrinfo(*) = raise(NotImplementedError)
  end

  $LOADED_FEATURES.push('socket.so', 'socket.rb', 'io/wait.so', 'io/wait.rb')
end

require 'rubygems'
require 'rubocop'
require 'fileutils'
require 'json'
require 'stringio'
require 'yaml'

# Runs RuboCop for the page. A run reads its request from /pg and answers
# with JSON: what to show, and the offenses for the editor's underlines.
module Playground
  # A leading dash would make the name an option.
  FILE_NAME = /\A\w[\w.-]{0,63}\z/
  REPORT = '/pg/report.json'

  # What each mode runs, as shown on the page. The diff views use the
  # offenses formatter: it marks each cop as safe or unsafe to correct, which
  # is the whole difference between -a and -A.
  ARGS = {
    'lint' => [],
    'diff' => %w[-a --diff --format offenses],
    'diff-all' => %w[-A --diff --format offenses],
    'fix' => %w[-a],
    'fix-all' => %w[-A]
  }.freeze

  module_function

  def run
    file, mode = read_request
    notes, config_args = prepare(file)
    status, stdout, stderr = cli(file, mode, config_args)
    JSON.generate(
      status:, notes:, command: command(file, mode), **output(stdout, stderr),
      offenses:, source: (File.read(file) if mode.start_with?('fix'))
    )
  rescue StandardError, SyntaxError => e
    JSON.generate(status: 2, notes: [], html: '', errors: CGI.escapeHTML("#{e.class}: #{e.message}"))
  end

  # The first run pays for checksumming RuboCop's sources and loading the
  # default config. Doing it during boot keeps the first real result quick.
  def warm_up
    File.write('/pg/request.json', JSON.generate(file: 'warm_up.rb', mode: 'lint'))
    File.write('/pg/source', "# frozen_string_literal: true\n\nputs 'hi'\n")
    File.write('/pg/config.yml', '')
    run
  end

  def read_request
    request = JSON.parse(File.read('/pg/request.json'))
    file = request.fetch('file')
    mode = request.fetch('mode')
    raise ArgumentError, "bad file name: #{file}" unless FILE_NAME.match?(file)
    raise ArgumentError, "bad mode: #{mode}" unless ARGS.key?(mode)

    [file, mode]
  end

  # Each run starts from a clean /work: the config, then the code. Returns
  # what write_config does.
  def prepare(file)
    Dir.children('/work').each { |name| File.delete("/work/#{name}") }
    FileUtils.rm_f(REPORT)
    File.write("/work/#{file}", File.read('/pg/source'))
    write_config(File.read('/pg/config.yml'))
  end

  # Plain runs print clang-style output and write a JSON report for the
  # editor. That report has to come first: RuboCop treats the last --format
  # as the main one, and JSON there would hide cop names.
  def cli(file, mode, config_args)
    args = ARGS[mode]
    args = ['--format', 'json', '--out', REPORT, '--format', 'clang', *args] if mode == 'lint'
    args = ['--format', 'clang', *args] unless args.include?('--format')
    capture { RuboCop::CLI.new.run([file, *args, *config_args, '--color', '--cache', 'false']) }
  end

  def capture
    out = $stdout = StringIO.new
    err = $stderr = StringIO.new
    [yield, out.string, err.string]
  rescue SystemExit => e
    [e.status, out.string, err.string]
  ensure
    $stdout = STDOUT
    $stderr = STDERR
  end

  def command(file, mode)
    ['rubocop', *ARGS[mode], file].join(' ')
  end

  def output(stdout, stderr)
    { html: render(stdout), errors: render(stderr), patch: stdout.match?(%r{^--- a/}) }
  end

  def render(text)
    RubocopHTML.terminal(text.strip.gsub(/\n{3,}/, "\n\n"), locations: true) { |name| docs_url(name) }
  end

  def docs_url(name)
    RubocopHTML.docs_url(name) if RuboCop::Cop::Registry.global.find_by_cop_name(name)
  end

  # The offenses of a plain run, each with its docs URL.
  def offenses
    return unless File.exist?(REPORT)

    JSON.parse(File.read(REPORT)).dig('files', 0, 'offenses').to_a.map do |offense|
      offense.merge('url' => docs_url(offense['cop_name']))
    end
  end

  # Writes the effective .rubocop.yml. Returns notes about anything dropped,
  # and extra arguments for the run.
  def write_config(raw)
    yaml, notes, args = Config.build(raw)
    File.write('/work/.rubocop.yml', yaml)
    [notes, args]
  end

  # Turns the .rubocop.yml from the page into one that's safe to run.
  module Config
    # Keys that would load code or files from outside the playground.
    BLOCKED_KEYS = %w[require plugins inherit_from inherit_gem].freeze

    module_function

    # The effective config as YAML, notes about anything dropped and extra
    # arguments for the run.
    def build(raw)
      data = parse(raw)
      dropped = BLOCKED_KEYS & data.keys
      data = data.except(*BLOCKED_KEYS)
      all_cops = data['AllCops'].is_a?(Hash) ? data['AllCops'] : {}
      data['AllCops'] = all_cops.merge('SuggestExtensions' => false, 'UseCache' => false)
      notes = dropped.map { |key| "#{key}: is ignored in the playground" }
      [erb_safe(YAML.dump(data)), notes, pending_cops_args(all_cops)]
    end

    def parse(raw)
      raise ArgumentError, "ERB isn't supported in the playground's .rubocop.yml" if raw.include?('<%')
      return {} if raw.strip.empty?

      data = YAML.safe_load(raw, permitted_classes: [Regexp, Symbol], aliases: true, filename: '.rubocop.yml')
      data ||= {}
      raise ArgumentError, '.rubocop.yml must be a mapping of cop names to settings' unless data.is_a?(Hash)

      data
    end

    # RuboCop runs .rubocop.yml through ERB. Raw ERB is refused up front, but a
    # YAML escape like "\x3C%" only becomes "<%" once parsed, so every "<%" in
    # the dumped config is escaped for ERB, which prints it back as "<%".
    def erb_safe(yaml)
      yaml.gsub('<%', '<%%')
    end

    # Without NewCops, pending cops stay off, as on the command line, but the
    # long notice listing every one of them would bury the actual output.
    def pending_cops_args(all_cops)
      all_cops.key?('NewCops') ? [] : ['--disable-pending-cops']
    end
  end
end
