# frozen_string_literal: true

require 'json'
require 'open3'

module Builders
  # Runs RuboCop on the small project in demo/ and keeps what it prints,
  # colors included, for the terminals on the home page. Nothing there is
  # typed up by hand, so it can't drift from what RuboCop actually prints.
  class DemoRuns < SiteBuilder
    include Demo

    RUNS = {
      lint: %w[],
      diff: %w[--diff lib/greeter.rb],
      fix: %w[-a],
      fix_all: %w[-A --diff],
      offenses: %w[-f offenses],
      worst: %w[-f worst],
      github: %w[-f github],
      json: %w[-f json],
      explain: %w[--explain Style/StringLiterals],
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
        site.data[:runs] = cache.getset(demo_key(__FILE__)) { run_all }
      end
    end

    private

    def run_all
      RUNS.map { |name, args| Thread.new { [name, run(name, args)] } }.to_h(&:value)
    end

    def run(name, args)
      in_demo_copy do |dir|
        output = rubocop(dir, name == :json ? args : [*args, '--color'])
        postprocess(name, ['rubocop', *args].join(' '), output.rstrip)
      end
    end

    def rubocop(dir, args)
      output, errors, status = Open3.capture3(*rubocop_command(*args, '--cache', 'false'), chdir: dir)
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
    # it out with jq, and one that comes with the edits that fix it.
    def json_sample(command, output)
      report = JSON.parse(output)
      file = report['files'].index { |entry| entry['offenses'].any? { |offense| offense.key?('correction') } }
      raise 'no offense in the demo comes with a correction' unless file

      offenses = report['files'][file]['offenses']
      index = offenses.index { |offense| offense.key?('correction') }
      { command: "#{command} | jq '.files[#{file}].offenses[#{index}]'", output: JSON.pretty_generate(offenses[index]) }
    end
  end
end
