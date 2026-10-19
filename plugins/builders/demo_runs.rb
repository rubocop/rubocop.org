# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

module Builders
  # Runs RuboCop on the small project in demo/ and keeps what it prints,
  # colors included, for the terminals on the home page. Nothing there is
  # typed up by hand, so it can't drift from what RuboCop actually prints.
  class DemoRuns < SiteBuilder
    DEMO_DIR = 'demo'

    RUNS = {
      lint: %w[],
      diff: %w[--diff lib/greeter.rb],
      fix: %w[-a],
      fix_all: %w[-A --diff],
      offenses: %w[-f offenses],
      worst: %w[-f worst],
      github: %w[-f github],
      json: %w[-f json],
      # How it works follows the offense in this file alone, which the other
      # runs leave out.
      walk: %w[lib/user.rb],
      walk_fix: %w[-a --diff lib/user.rb]
    }.freeze

    # The runs that print a diff skip the offense listing, which the page
    # already shows elsewhere.
    ELIDED = %i[diff fix_all walk_fix].freeze

    def build
      hook :site, :post_read do
        site.data[:runs] = cache.getset(cache_key) { run_all }
      end
    end

    private

    # The output depends on the demo files, every gem in the bundle and the
    # postprocessing in this file.
    def cache_key
      inputs = [File.read(site.in_root_dir('Gemfile.lock')), File.read(__FILE__), *demo_files]
      Digest::SHA256.hexdigest(inputs.join("\0"))
    end

    def demo_files
      files = Dir.glob('**/*', File::FNM_DOTMATCH, base: demo_path).sort.select { |f| File.file?(File.join(demo_path, f)) }
      files.map { |f| "#{f}\0#{File.read(File.join(demo_path, f))}" }
    end

    def demo_path
      site.in_root_dir(DEMO_DIR)
    end

    def run_all
      RUNS.map { |name, args| Thread.new { [name, run(name, args)] } }.to_h(&:value)
    end

    # Each run gets a fresh copy, since -a rewrites the files.
    def run(name, args)
      Dir.mktmpdir do |dir|
        FileUtils.cp_r("#{demo_path}/.", dir)
        output = rubocop(dir, name == :json ? args : [*args, '--color'])
        postprocess(name, ['rubocop', *args].join(' '), output.rstrip)
      end
    end

    def rubocop(dir, args)
      command = [RbConfig.ruby, '-rbundler/setup', Gem.bin_path('rubocop', 'rubocop'), *args, '--cache', 'false']
      output, errors, status = Open3.capture3({ 'BUNDLE_GEMFILE' => site.in_root_dir('Gemfile') }, *command, chdir: dir)
      # 1 just means offenses. Anything else is RuboCop failing, and its
      # partial output shouldn't end up on the home page.
      raise "rubocop #{args.join(' ')} exited with #{status.exitstatus}: #{errors}" if status.exitstatus > 1

      output
    end

    def postprocess(name, command, output)
      return json_sample(command, output) if name == :json

      { command:, output: ELIDED.include?(name) ? elide_offenses(output) : output }
    end

    # Replaces "Offenses: ..." up to the summary line with an ellipsis.
    def elide_offenses(output)
      output.sub(/^Offenses:\n.*?\n\n(?=\d+ files? inspected)/m, "\e[2m...\e[0m\n\n")
    end

    # The whole JSON report is long, so show one offense the way you'd pull
    # it out with jq.
    def json_sample(command, output)
      report = JSON.parse(output)
      index = report['files'].index { |file| file['offenses'].any? }
      offense = report['files'][index]['offenses'].first
      { command: "#{command} | jq '.files[#{index}].offenses[0]'", output: JSON.pretty_generate(offense) }
    end
  end
end
