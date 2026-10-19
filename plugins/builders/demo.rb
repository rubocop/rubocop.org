# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'

module Builders
  # The small project in demo/ the home page shows RuboCop at work on, for
  # the builders that run the bundled RuboCop on it.
  module Demo
    DIR = 'demo'

    def demo_path(path = '.')
      site.in_root_dir(DIR, path)
    end

    # What RuboCop prints for the demo depends on its files, every gem in the
    # bundle, how this module runs it and what the builder makes of it.
    def demo_key(builder_file)
      files = Dir.glob('**/*', File::FNM_DOTMATCH, base: demo_path).sort.select { |file| File.file?(demo_path(file)) }
      inputs = [site.in_root_dir('Gemfile.lock'), __FILE__, builder_file].map { |path| File.read(path) }
      Digest::SHA256.hexdigest([*inputs, *files.map { |file| "#{file}\0#{File.read(demo_path(file))}" }].join("\0"))
    end

    # A fresh copy each time, since -a rewrites the files. It's also out of
    # reach of the site's own config, which excludes the demo.
    def in_demo_copy
      Dir.mktmpdir do |dir|
        FileUtils.cp_r("#{demo_path}/.", dir)
        yield dir
      end
    end

    # The bundled RuboCop, with the environment that finds the site's bundle.
    def rubocop_command(*args)
      [{ 'BUNDLE_GEMFILE' => site.in_root_dir('Gemfile') }, RbConfig.ruby, '-rbundler/setup',
       Gem.bin_path('rubocop', 'rubocop'), *args]
    end
  end
end
