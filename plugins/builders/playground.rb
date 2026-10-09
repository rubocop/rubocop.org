# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'rubygems/package'
require 'zlib'

module Builders
  # Everything the playground loads besides its JavaScript: the ruby.wasm
  # runtime (from jsDelivr) and an archive of the RuboCop from this site's
  # bundle, with its runtime dependencies, which the worker mounts as GEM_HOME.
  class Playground < SiteBuilder
    # The runtime ships in step with its JS glue, @ruby/wasm-wasi, so it's
    # loaded at the glue's version and the two can't drift apart.
    GLUE_PACKAGE = 'node_modules/@ruby/wasm-wasi/package.json'
    RUBY = '4.0'
    RUNTIME_URL = "https://cdn.jsdelivr.net/npm/@ruby/#{RUBY}-wasm-wasi@%<version>s/dist/ruby+stdlib.wasm".freeze
    # Uncompressed, for the progress bar only, so being a little off is fine.
    RUNTIME_SIZE = 32_555_374

    # Gems that ruby.wasm already ships as default gems, compiled in.
    PROVIDED_BY_RUBY = %w[json prism].freeze

    # Only needed for --lsp, which the playground doesn't use. Its gemspec
    # stays so RubyGems can still activate rubocop.
    SPEC_ONLY = %w[language_server-protocol].freeze

    SKIPPED = Regexp.union(
      /\.(so|bundle|dll|o)\z/,
      # grammars for Rubies older than anything RuboCop can target
      %r{\Alib/parser/(ruby18|ruby19|macruby|rubymotion)\.rb\z}
    )

    def build
      hook :site, :post_read do
        archive = File.join(cache_root, 'playground', archive_name)
        write_archive(archive)
        serve(archive)
        site.data[:playground] = data(archive)
      end
    end

    private

    def cache_root
      File.join(site.cache_dir, 'playground')
    end

    # Served next to the page, as /playground/<name>.
    def serve(archive)
      site.static_files << Bridgetown::StaticFile.new(site, cache_root, 'playground', File.basename(archive))
    end

    def data(archive)
      version = JSON.parse(File.read(site.in_root_dir(GLUE_PACKAGE))).fetch('version')
      {
        ruby: RUBY,
        runtime_url: format(RUNTIME_URL, version:),
        runtime_size: RUNTIME_SIZE,
        bundle: File.basename(archive),
        bundle_size: File.size(archive)
      }
    end

    def specs
      @specs ||= collect(Gem.loaded_specs.fetch('rubocop'), {}).values.sort_by(&:name)
    end

    def collect(spec, found)
      return found if found.key?(spec.name) || PROVIDED_BY_RUBY.include?(spec.name)

      found[spec.name] = spec
      spec.runtime_dependencies.each { |dep| collect(Gem.loaded_specs.fetch(dep.name), found) }
      found
    end

    # The name carries a digest of the gems and of the packing rules in this
    # file, so browsers can cache the archive for as long as they like, and
    # builds reuse it while neither changes.
    def archive_name
      digest = Digest::SHA256.hexdigest([*specs.map(&:full_name), File.read(__FILE__)].join("\0"))[0, 10]
      "rubocop-#{RuboCop::Version::STRING}-#{digest}.tar.gz"
    end

    def write_archive(path)
      return if File.exist?(path)

      FileUtils.mkdir_p(File.dirname(path))
      File.open("#{path}.tmp", 'wb') do |io|
        Zlib::GzipWriter.wrap(io, Zlib::BEST_COMPRESSION) do |gzip|
          Gem::Package::TarWriter.new(gzip) { |tar| specs.each { |spec| add_gem(tar, spec) } }
        end
      end
      File.rename("#{path}.tmp", path)
    end

    def add_gem(tar, spec)
      # ruby.wasm can't load native extensions. racc falls back to pure Ruby,
      # but only if RubyGems doesn't skip it for having unbuilt extensions.
      gemspec = spec.dup.tap { |s| s.extensions = [] }.to_ruby
      add(tar, "specifications/#{spec.full_name}.gemspec", gemspec)

      files(spec).each do |file|
        add(tar, "gems/#{spec.full_name}/#{file}", File.binread(File.join(spec.full_gem_path, file)))
      end
    end

    def files(spec)
      patterns = ['{LICENSE,MIT-LICENSE,COPYING,BSDL}*', 'data/**/*']
      patterns << 'lib/**/*' unless SPEC_ONLY.include?(spec.name)
      patterns.push('config/**/*', 'exe/*') if spec.name == 'rubocop'
      Dir.glob(patterns, base: spec.full_gem_path).sort.select do |file|
        File.file?(File.join(spec.full_gem_path, file)) && !file.match?(SKIPPED)
      end
    end

    def add(tar, name, content)
      tar.add_file_simple(name, 0o644, content.bytesize) { |io| io.write(content) }
    end
  end
end
