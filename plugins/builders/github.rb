# frozen_string_literal: true

module Builders
  # Fetches the latest releases, the star count and the number of
  # contributors from the GitHub API at build time. Set GITHUB_TOKEN to avoid
  # the anonymous rate limit.
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
        site.data.merge!(
          releases: hourly('releases') { fetch_releases } || [],
          stars: hourly('stars') { api('')&.fetch('stargazers_count') },
          contributors: hourly('contributors') { contributors }
        )
      end
    end

    private

    def fetch_releases
      api('/releases', per_page: RELEASE_COUNT)&.map { parse_release(it) }
    end

    def api(path, params = {})
      body = download("#{API_URL}#{path}", params:, headers:)
      body && JSON.parse(body)
    end

    # GitHub lists contributors a page at a time, so with one to a page the
    # last page's number is the count. Commits from addresses without a
    # GitHub account count too.
    def contributors
      response = get("#{API_URL}/contributors", params: { per_page: 1, anon: true }, headers:)
      response && last_page(response.headers['link'])
    end

    def last_page(link)
      link.to_s[/[?&]page=(\d+)>; rel="last"/, 1]&.to_i
    end

    def headers
      ENV['GITHUB_TOKEN'] ? { 'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}" } : {}
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
