# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/helpers'

RSpec.describe Builders::Helpers do
  subject(:helpers) do
    described_class.allocate.tap do |builder|
      data = HashWithDotAccess::Hash.new(releases:, posts:)
      builder.define_singleton_method(:site) { Struct.new(:data).new(data) }
    end
  end

  let(:releases) { [] }
  let(:posts) do
    [
      { url: 'https://metaredux.com/posts/2026/09/11/rubocop-1-91.html', date: Date.parse('2026-09-11') },
      { url: 'https://metaredux.com/posts/2026/08/05/rubocop-1-89.html', date: Date.parse('2026-08-05') }
    ]
  end

  def release(version, prerelease: false, date: '2026-09-10')
    { version:, prerelease:, date: Date.parse(date), url: "https://example.com/v#{version}" }
  end

  describe '#latest_release' do
    let(:releases) do
      [release('2.0.0.rc1', prerelease: true), release('1.90.2', date: '2026-09-20'), release('1.91.0')]
    end

    it 'skips prereleases and backports' do
      expect(helpers.latest_release[:version]).to eq('1.91.0')
    end
  end

  describe '#release_post' do
    it 'finds the write-up by its address' do
      expect(helpers.release_post(release('1.91.1'))[:url]).to end_with('rubocop-1-91.html')
    end

    it "doesn't take a post that only mentions the version" do
      expect(helpers.release_post(release('2.0.0'))).to be_nil
    end
  end
end
