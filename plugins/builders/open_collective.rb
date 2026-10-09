# frozen_string_literal: true

module Builders
  # Fetches the backers on Open Collective for the funding section. Its
  # avatar badges would be simpler, but they come without names, so the
  # links would be blank to a screen reader.
  class OpenCollective < SiteBuilder
    MEMBERS_URL = 'https://opencollective.com/rubocop/members/all.json'

    # Resized avatars, with a placeholder for backers who never set one.
    IMAGES_URL = 'https://images.opencollective.com'

    SHOWN = { organizations: 20, individuals: 30 }.freeze

    def build
      hook :site, :post_read do
        site.data[:backers] = hourly('backers') { fetch_backers } || {}
      end
    end

    private

    # Nice to have, like the news feed, so it doesn't fail a deploy.
    def fetch_backers
      body = download(MEMBERS_URL, required: false)
      body && backers(JSON.parse(body))
    rescue JSON::ParserError => e
      download_failed("#{MEMBERS_URL} sent bad JSON: #{e.message}", false)
    end

    # The biggest backers first, the way Open Collective's own badges go.
    def backers(members)
      individuals, organizations = unique_backers(members).sort_by { -donated(it) }.partition { it['type'] == 'USER' }

      {
        organizations: organizations.first(SHOWN[:organizations]).map { backer(it, 'logo') },
        individuals: individuals.first(SHOWN[:individuals]).map { backer(it, 'avatar') }
      }
    end

    # Someone backing through several tiers is listed once per tier.
    def unique_backers(members)
      members.select { it['role'] == 'BACKER' && slug(it) }
             .group_by { it['profile'] }
             .map { |_, entries| entries.max_by { donated(it) } }
    end

    def donated(member) = member['totalAmountDonated'].to_f

    def backer(member, image)
      website = member['website'].to_s
      {
        name: member['name'],
        url: website.match?(%r{\Ahttps?://}) ? website : member['profile'],
        image: "#{IMAGES_URL}/#{slug(member)}/#{image}/72.png"
      }
    end

    def slug(member)
      member['profile'].to_s[%r{\Ahttps://opencollective\.com/([\w-]+)\z}, 1]
    end
  end
end
