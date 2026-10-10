# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/rubocop_html'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/helpers'

RSpec.describe Builders::Helpers do
  subject(:helpers) do
    described_class.allocate.tap do |builder|
      data = HashWithDotAccess::Hash.new(releases:, posts:, cop_urls: {})
      metadata = HashWithDotAccess::Hash.new(title: 'RuboCop', tagline: 'The Ruby linter')
      builder.define_singleton_method(:site) { Struct.new(:data, :metadata).new(data, metadata) }
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

  describe '#page_title' do
    it 'puts the site name after the page' do
      expect(helpers.page_title('Cops')).to eq('Cops | RuboCop')
    end

    it 'uses the tagline for a page with an empty title' do
      expect(helpers.page_title('')).to eq('RuboCop: The Ruby linter')
    end
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

  describe '#terminal_tabs' do
    let(:runs) do
      { 'rubocop' => { command: 'rubocop', output: '' }, 'rubocop -a' => { command: 'rubocop -a', output: '' } }
    end

    it 'ties each tab to its panel and shows the first one', :aggregate_failures do
      html = helpers.terminal_tabs('run', runs)

      expect(html).to include('role="tab" id="run-tab-1" aria-selected="false" aria-controls="run-1">rubocop -a<')
      expect(html).to include('<pre id="run-0" role="tabpanel" aria-labelledby="run-tab-0" tabindex="0">')
      expect(html).to include('<pre id="run-1" role="tabpanel" aria-labelledby="run-tab-1" tabindex="0" hidden="true">')
    end
  end
end
