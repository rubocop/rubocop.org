# frozen_string_literal: true

module Builders
  # Provides the `vite_tags` helper, which renders the frontend entrypoint from
  # the Vite dev server when it's running, or from the build manifest otherwise.
  class Vite < SiteBuilder
    ENTRY = 'javascript/index.js'

    def build
      helper :vite_tags
    end

    def vite_tags
      dev_server_url ? dev_server_tags : manifest_tags
    end

    private

    def dev_server_url
      file = site.in_root_dir('.bridgetown-cache', 'frontend-bundling', 'vite-dev-server')
      File.read(file).strip if !Bridgetown.env.production? && File.exist?(file)
    end

    def dev_server_tags
      base = "#{dev_server_url}#{static_path}"

      <<~HTML.html_safe
        <script type="module" src="#{base}@vite/client"></script>
        <script type="module" src="#{base}#{ENTRY}"></script>
      HTML
    end

    def manifest_tags
      entry = manifest.fetch(ENTRY)
      stylesheets = entry.fetch('css', []).map do |file|
        %(<link rel="stylesheet" href="#{static_path}#{file}" />)
      end

      [*stylesheets, %(<script type="module" src="#{static_path}#{entry['file']}"></script>)].join("\n").html_safe
    end

    def manifest
      file = site.in_dest_dir('_bridgetown', 'static', '.vite', 'manifest.json')
      raise "Vite manifest not found at #{file}, run `bin/bridgetown frontend:build`" unless File.exist?(file)

      JSON.parse(File.read(file))
    end

    def static_path
      "#{site.base_path.chomp('/')}/_bridgetown/static/"
    end
  end
end
