# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/rubocop_html'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/cops'

RSpec.describe Builders::Cops do
  subject(:builder) { described_class.allocate }

  let(:config) { RuboCop::ConfigLoader.default_configuration }

  def describe_cop(name)
    builder.send(:describe, RuboCop::Cop::Registry.global.find_by_cop_name(name), config)
  end

  it 'links a cop to the guideline it enforces, as RuboCop does', :aggregate_failures do
    expect(describe_cop('Style/AndOr')[:guide]).to eq('https://rubystyle.guide#no-and-or-or')
    expect(describe_cop('Lint/DuplicateMethods')[:guide]).to be_nil
  end

  it "links a plugin's cop to its own style guide, whatever core cop shares its guideline", :aggregate_failures do
    config = builder.send(:default_config)
    guide = ->(name) { builder.send(:guide_url, RuboCop::Cop::Registry.global.find_by_cop_name(name), config, config.for_cop(name)) }

    expect(guide['Style/ClassCheck']).to eq('https://rubystyle.guide#is-a-vs-kind-of')
    expect(guide['RSpec/ClassCheck']).to eq('https://rspec.rubystyle.guide#is-a-vs-kind-of')
  end

  it 'marks the cops that look across files with the project index', :aggregate_failures do
    expect(describe_cop('Lint/DuplicateMethods')[:index]).to be(true)
    expect(describe_cop('Lint/NameTypo')[:index]).to be(true)
    expect(describe_cop('Style/StringLiterals')[:index]).to be(false)
  end
end
