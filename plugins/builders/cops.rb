# frozen_string_literal: true

require 'rubocop'
require 'tmpdir'

module Builders
  # Loads RuboCop and its official plugins and walks the cop registry, so the
  # cop index and the home page always describe the RuboCop the site is built
  # with. Upgrading the gems in the Gemfile is all it takes to refresh them.
  class Cops < SiteBuilder
    def build
      hook :site, :post_read do
        publish(load_cops)
      end
    end

    private

    def publish(cops)
      site.data.merge!(
        cops:,
        cop_urls: cops.to_h { |cop| [cop[:name], cop[:url]] },
        departments: departments(cops),
        rubocop: versions
      )
    end

    # The official plugins with docs on docs.rubocop.org: the :plugins group
    # in the Gemfile.
    def plugins
      @plugins ||= Bundler.definition.dependencies.select { |dep| dep.groups.include?(:plugins) }.map(&:name)
    end

    def versions
      { version: RuboCop::Version::STRING, plugins: plugins.to_h { |name| [name, Gem.loaded_specs[name].version.to_s] } }
    end

    def load_cops
      config = default_config
      cops = RuboCop::Cop::Registry.global.map { |cop| describe(cop, config) }
      cops.sort_by { |cop| [plugin_rank(cop), cop[:department], cop[:name]] }
    end

    # The defaults of RuboCop plus every plugin, as a project that enables all
    # of them would see them.
    def default_config
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.rubocop.yml')
        File.write(path, { 'plugins' => plugins }.to_yaml)
        RuboCop::ConfigLoader.configuration_from_file(path, check: false)
      end
    end

    def describe(cop, config)
      settings = config.for_cop(cop)
      plugin = plugin_for(cop)
      {
        name: cop.cop_name, department: cop.department.to_s, plugin:,
        description: settings['Description'].to_s, status: status(settings['Enabled']),
        autocorrect: autocorrect(cop, settings), added: settings['VersionAdded'].to_s,
        url: RubocopHTML.docs_url(cop.cop_name, plugin), index: project_index?(cop)
      }
    end

    # The cops that use the project index include a mixin of it. The index
    # is experimental, so a RuboCop without the mixin just has none.
    def project_index?(cop)
      RuboCop::Cop.const_defined?(:ProjectIndexHelp) && cop.include?(RuboCop::Cop::ProjectIndexHelp)
    end

    def status(enabled)
      case enabled
      when true then 'enabled'
      when 'pending' then 'pending'
      else 'disabled'
      end
    end

    # -a only applies corrections from cops that are safe and whose
    # corrections are safe. Everything else needs -A.
    def autocorrect(cop, settings)
      return unless cop.support_autocorrect?

      settings['Safe'] == false || settings['SafeAutoCorrect'] == false ? 'unsafe' : 'safe'
    end

    # The gem whose directory the cop's source lives in, which also works for
    # gems from git or a local path.
    def plugin_for(cop)
      path, = Module.const_source_location(cop.name)
      plugins.find { |name| path.start_with?("#{Gem.loaded_specs[name].full_gem_path}/") } || 'rubocop'
    end

    def plugin_rank(cop)
      cop[:plugin] == 'rubocop' ? 0 : 1
    end

    # Every department, in index order.
    def departments(cops)
      cops.chunk_while { |a, b| a[:department] == b[:department] }.map do |members|
        department, plugin = members.first.values_at(:department, :plugin)
        { name: department, plugin:, url: RubocopHTML.department_url(department, plugin), cops: members }
      end
    end
  end
end
