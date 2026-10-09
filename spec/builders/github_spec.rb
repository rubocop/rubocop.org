# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/github'

RSpec.describe Builders::Github do
  subject(:builder) { described_class.allocate }

  let(:notes) do
    <<~NOTES
      ### New features

      * [#1](https://example.com): Add new `Lint/Foo` cop. ([@a][])
      * [#2](https://example.com): Add new `Capybara/RSpec/Bar` cop. ([@b][])

      ### Bug fixes

      * [#3](https://example.com): Fix something. ([@c][])
    NOTES
  end

  it 'counts the entries in each section of the release notes' do
    expect(builder.send(:summarize, notes)).to eq('2 new features, 1 bug fix')
  end

  it 'picks out the new cops' do
    release = { 'tag_name' => 'v1.92.0', 'html_url' => 'u', 'prerelease' => false,
                'published_at' => '2026-10-01T10:00:00Z', 'body' => notes }

    expect(builder.send(:parse_release, release)[:new_cops]).to eq(%w[Lint/Foo Capybara/RSpec/Bar])
  end
end
