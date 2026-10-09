# frozen_string_literal: true

module Builders
  # Fetches the latest releases and the star count from the GitHub API at
  # build time. Set GITHUB_TOKEN to avoid the anonymous rate limit.
  class Github < SiteBuilder
    API_URL = 'https://api.github.com/repos/rubocop/rubocop'

    RELEASE_COUNT = 5

    SECTIONS = {
      'New features' => ['new feature', 'new features'],
      'Bug fixes' => ['bug fix', 'bug fixes'],
      'Changes' => %w[change changes]
    }.freeze

    def build
      hook :site, :post_read do
        site.data[:releases] = hourly('releases') { fetch_releases } || []
        site.data[:stars] = hourly('stars') { api('')&.fetch('stargazers_count') }
      end
    end

    private

    def fetch_releases
      api('/releases', per_page: RELEASE_COUNT)&.map { parse_release(it) }
    end

    def api(path, params = {})
      headers = ENV['GITHUB_TOKEN'] ? { 'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}" } : {}
      body = download("#{API_URL}#{path}", params:, headers:)
      body && JSON.parse(body)
    end

    def parse_release(release)
      body = release['body'].to_s
      {
        version: release['tag_name'].delete_prefix('v'),
        prerelease: release['prerelease'],
        url: release['html_url'],
        date: Date.parse(release['published_at']),
        summary: summarize(body),
        new_cops: body.scan(%r{Add new `([A-Z]\w*(?:/[A-Z]\w*)+)` cop}).flatten
      }
    end

    # "4 new features, 12 bug fixes, 2 changes", counted from the notes.
    def summarize(body)
      sections = body.split(/^### /).drop(1)
      SECTIONS.filter_map do |title, (one, many)|
        section = sections.find { |s| s.start_with?(title) }
        count = section&.scan(/^\* /)&.size.to_i
        "#{count} #{count == 1 ? one : many}" if count.positive?
      end.join(', ')
    end
  end
end
