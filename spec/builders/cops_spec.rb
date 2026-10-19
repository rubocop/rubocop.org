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

  it 'marks the cops that look across files with the project index', :aggregate_failures do
    expect(describe_cop('Lint/DuplicateMethods')[:index]).to be(true)
    expect(describe_cop('Lint/NameTypo')[:index]).to be(true)
    expect(describe_cop('Style/StringLiterals')[:index]).to be(false)
  end
end
