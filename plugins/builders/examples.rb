# frozen_string_literal: true

require 'digest'
require 'stringio'
require 'tmpdir'
require 'yaml'

module Builders
  # The first example in the docs of each of RuboCop's own cops, with a
  # config that turns on just that cop, for the "try" links on the cop index.
  # They open in the playground, which runs RuboCop without its plugins. An
  # example that the cop finds nothing in when it runs alone gets no link.
  class Examples < SiteBuilder
    # As in the playground's own example config.
    TARGET_RUBY_VERSION = 3.4

    def build
      hook :site, :post_read do
        inputs = [site.in_root_dir('Gemfile.lock'), __FILE__].map { |path| File.read(path) }
        site.data[:examples] = cache.getset(Digest::SHA256.hexdigest(inputs.join("\0"))) { examples }
      end
    end

    private

    def examples
      with_core_defaults do
        Dir.mktmpdir { |dir| core_cops.filter_map { |cop| example(cop, dir) }.to_h }
      end
    end

    # Loading the plugins, as the cop index does, adds their defaults to
    # RuboCop's. The playground runs without them, so the examples are
    # checked against RuboCop's own.
    def with_core_defaults
      merged = RuboCop::ConfigLoader.default_configuration
      RuboCop::ConfigLoader.default_configuration = nil
      yield
    ensure
      RuboCop::ConfigLoader.default_configuration = merged
    end

    def core_cops
      gem = "#{Gem.loaded_specs['rubocop'].full_gem_path}/"
      RuboCop::Cop::Registry.global.select { |cop| Module.const_source_location(cop.name).first.start_with?(gem) }
    end

    def example(cop, dir)
      title, code = tagged_examples(cop).first
      return unless code

      defaults = RuboCop::ConfigLoader.default_configuration.for_cop(cop)
      config = config(cop, setting(title, defaults))
      file = file_name(defaults)
      [cop.cop_name, { code:, config:, file: }] if offends?(cop, code, config, File.join(dir, file))
    end

    # The @example tags in the docs, as titles and code.
    def tagged_examples(cop)
      docs(cop).slice_before { |text| text.start_with?('@') }.filter_map do |tag, *lines|
        title = tag[/\A@example ?(.*)/, 1] or next
        [title.strip, "#{lines.map { |text| text.delete_prefix('  ') }.join("\n").sub(/\A\n+/, '').rstrip}\n"]
      end
    end

    # The comment above the cop's class, without the #s.
    def docs(cop)
      path, line = Module.const_source_location(cop.name)
      comment = File.readlines(path, chomp: true).first(line - 1).reverse.take_while { |text| text.match?(/\A\s*#/) }
      comment.reverse.map { |text| text.sub(/\A\s*# ?/, '') }
    end

    # An example titled with a setting, "EnforcedStyle: comparison", shows
    # the cop with that setting.
    def setting(title, defaults)
      key, value = title.match(/\A(\w+): (\S+|\[.*\])(?: \(default\))?\z/)&.captures
      defaults.key?(key) ? { key => YAML.safe_load(value) } : {}
    rescue Psych::Exception
      {}
    end

    def config(cop, setting)
      all_cops = { 'DisabledByDefault' => true, 'TargetRubyVersion' => TARGET_RUBY_VERSION }
      yaml = { 'AllCops' => all_cops, cop.cop_name => { 'Enabled' => true, **setting } }.to_yaml
      "# Just #{cop.cop_name}, on the example from its docs.\n#{yaml.delete_prefix("---\n")}"
    end

    # Cops that only look at some files, like Gemfiles, get one of those,
    # by its plain name when it has one.
    def file_name(defaults)
      names = Array(defaults['Include']).map { |pattern| File.basename(pattern) }
      names.find { |name| !name.include?('*') } || names.first&.sub('*', 'example') || 'example.rb'
    end

    # Runs just the cop on the example, as the playground would, where an
    # offense a comment disables doesn't show. Cops warn about what they
    # can't make sense of, which isn't news here.
    def offends?(cop, code, yaml, path)
      config = load_config(yaml, File.dirname(path))
      report = quietly { RuboCop::Cop::Team.mobilize([cop], config, raise_error: true).investigate(source(code, path, config)) }
      report.offenses.any? { |offense| offense.cop_name == cop.cop_name && !offense.disabled? }
    rescue StandardError
      false
    end

    def source(code, path, config)
      source = RuboCop::ProcessedSource.new(code, config.target_ruby_version, path, parser_engine: config.parser_engine)
      source.config = config
      source.registry = RuboCop::Cop::Registry.global
      source
    end

    def load_config(yaml, dir)
      path = File.join(dir, '.rubocop.yml')
      File.write(path, yaml)
      RuboCop::ConfigLoader.configuration_from_file(path, check: false)
    end

    def quietly
      stderr = $stderr
      $stderr = StringIO.new
      yield
    ensure
      $stderr = stderr
    end
  end
end
