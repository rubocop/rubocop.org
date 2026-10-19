# frozen_string_literal: true

require 'bridgetown'
require 'json'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/demo'
require_relative '../../plugins/builders/demo_runs'

RSpec.describe Builders::DemoRuns do
  subject(:builder) { described_class.allocate }

  let(:report) do
    {
      files: [
        { path: 'a.rb', offenses: [] },
        { path: 'b.rb', offenses: [{ cop_name: 'Naming/MethodName', correctable: false },
                                   { cop_name: 'Style/StringLiterals', correctable: true, correction: {} }] }
      ]
    }
  end

  it 'samples the first offense that comes with a correction', :aggregate_failures do
    sample = builder.send(:json_sample, 'rubocop -f json', JSON.generate(report))

    expect(sample[:command]).to eq("rubocop -f json | jq '.files[1].offenses[1]'")
    expect(JSON.parse(sample[:output])['cop_name']).to eq('Style/StringLiterals')
  end
end
