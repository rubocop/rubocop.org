# frozen_string_literal: true

require 'rexml/document'

module Builders
  # Fetches the RuboCop posts on Meta Redux, where the bigger releases get a
  # write-up. The news list on the home page mixes them with the releases.
  class News < SiteBuilder
    FEED_URL = 'https://metaredux.com/feed.xml'
    CATEGORY = 'RuboCop'

    def build
      hook :site, :post_read do
        site.data[:posts] = hourly('posts') { fetch_posts } || []
      end
    end

    private

    # The feed is nice to have, so it doesn't fail a deploy.
    def fetch_posts
      body = download(FEED_URL, required: false)
      return unless body

      REXML::Document.new(body).get_elements('//entry').filter_map { |entry| post(entry) if rubocop?(entry) }
    rescue StandardError => e
      Bridgetown.logger.warn('News:', "Meta Redux feed failed: #{e.message}")
      nil
    end

    def rubocop?(entry)
      entry.get_elements('category').any? { |category| category.attributes['term'] == CATEGORY }
    end

    def post(entry)
      {
        kind: 'post',
        title: entry.get_text('title').value,
        url: entry.get_elements('link').first.attributes['href'],
        date: Date.parse(entry.get_text('published').value)
      }
    end
  end
end
