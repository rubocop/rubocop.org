# frozen_string_literal: true

# The base class for the builders in plugins/builders.
class SiteBuilder < Bridgetown::Builder
  def cache
    @cache ||= Bridgetown::Cache.new(self.class.name)
  end

  # Keeps what came over the network for an hour in development, so rebuilds
  # don't fetch everything again. Production always fetches, and failures
  # are never kept.
  def hourly(key)
    return yield if Bridgetown.env.production?

    key = "#{key}-#{Time.now.strftime('%Y%m%d%H')}"
    return cache[key] if cache.key?(key)

    yield.tap { |value| cache[key] = value unless value.nil? }
  end

  # Returns the body, or nil after a warning. In production a required
  # download raises instead, so a deploy never goes out with missing data and
  # the previous site stays up.
  def download(url, **)
    get(url, **)&.body
  end

  # The same, but the whole response, headers and all.
  def get(url, params: {}, headers: {}, required: true)
    response = Faraday.get(url, params, headers)
    return response if response.success?

    download_failed("#{url} returned #{response.status}", required)
  rescue Faraday::Error => e
    download_failed("#{url} failed: #{e.message}", required)
  end

  private

  def download_failed(message, required)
    raise message if required && Bridgetown.env.production?

    Bridgetown.logger.warn("#{self.class.name.split('::').last}:", message)
    nil
  end
end
