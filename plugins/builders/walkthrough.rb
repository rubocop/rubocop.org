# frozen_string_literal: true

require 'rubocop'

module Builders
  # The first steps of "How it works", for the offense in the demo's
  # lib/user.rb: the tree RuboCop parses the file into, and the node the cop's
  # pattern matches in it, both straight from the bundled RuboCop. DemoRuns
  # records the runs that report the offense and fix it.
  class Walkthrough < SiteBuilder
    include Demo

    FILE = 'lib/user.rb'
    COP = RuboCop::Cop::Style::NilComparison
    MATCHER = :nil_comparison?

    def build
      hook :site, :post_read do
        site.data[:walkthrough] = { parse: { output: parse }, match: { output: match } }
      end
    end

    private

    # The file, then its tree.
    def parse
      "\e[2m# #{FILE}\e[0m\n#{source}\n\e[2m# the tree RuboCop inspects\e[0m\n#{tree}"
    end

    # The line of the cop that defines its pattern, then the tree, with all
    # but the pattern and the node it matches dimmed.
    def match
      definition, pattern = matcher
      "\e[2m# #{COP.cop_name}\n#{mark(definition, pattern)}\n\n#{mark(tree, matched_node)}"
    end

    # The line of the cop that defines its pattern, and where the pattern is
    # in it.
    def matcher
      path, line = COP.instance_method(MATCHER).source_location
      definition = File.readlines(path)[line - 1].strip
      pattern = parsed(definition).last_argument.source_range
      [definition, pattern.begin_pos...pattern.end_pos]
    end

    # Where the node the cop matches is in the tree.
    def matched_node
      cop = COP.new
      node = ast.each_node.find { |candidate| cop.public_send(MATCHER, candidate) }
      raise "#{COP.cop_name} matches nothing in #{FILE}" unless node

      place(node)
    end

    # A node prints the same on its own as in its tree, given the depth it's
    # indented to there.
    def place(node)
      text = node.to_sexp(node.each_ancestor.count)
      start = tree.index(text)
      (start + text[/\A */].size)...(start + text.size)
    end

    # Bold yellow, so it doesn't only stand out by color, with the rest dim.
    def mark(text, range)
      "\e[2m#{text[...range.begin]}\e[1;33m#{text[range]}\e[22;2m#{text[range.end..]}\e[0m"
    end

    def source = File.read(demo_path(FILE))
    def ast = @ast ||= parsed(source)
    def tree = ast.to_s

    # Parsed the way RuboCop parses the demo.
    def parsed(code)
      ruby = demo_config.target_ruby_version
      RuboCop::AST::ProcessedSource.new(code, ruby, parser_engine: demo_config.parser_engine).ast
    end

    # Not config, which Bridgetown's builders already have.
    def demo_config
      @demo_config ||= RuboCop::ConfigLoader.configuration_from_file(demo_path('.rubocop.yml'), check: false)
    end
  end
end
