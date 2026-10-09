# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/open_collective'

RSpec.describe Builders::OpenCollective do
  subject(:backers) { described_class.allocate.send(:backers, members) }

  def member(slug, total, type: 'USER', role: 'BACKER', website: nil)
    { 'profile' => "https://opencollective.com/#{slug}", 'name' => slug.capitalize, 'type' => type,
      'role' => role, 'totalAmountDonated' => total, 'website' => website }
  end

  let(:members) do
    [
      member('small', 10),
      member('big', 500),
      member('big', 900),
      member('acme', 300, type: 'ORGANIZATION', website: 'https://acme.example'),
      member('fund', 700, type: 'FUND'),
      member('admin', 0, role: 'ADMIN')
    ]
  end

  it 'lists each backer once, biggest first' do
    expect(backers[:individuals].map { it[:name] }).to eq(%w[Big Small])
  end

  it 'counts funds and collectives as organizations' do
    expect(backers[:organizations].map { it[:name] }).to eq(%w[Fund Acme])
  end

  it 'links to the website, or else the Open Collective profile' do
    expect(backers[:organizations].map { it[:url] }).to eq(%w[https://opencollective.com/fund https://acme.example])
  end

  it 'uses the resized avatars' do
    expect(backers[:individuals].first[:image]).to eq('https://images.opencollective.com/big/avatar/72.png')
  end

  context 'with a website that is not a web address' do
    let(:members) { [member('sneaky', 5, website: 'javascript:alert(1)')] }

    it 'links to the profile instead' do
      expect(backers[:individuals].first[:url]).to eq('https://opencollective.com/sneaky')
    end
  end
end
