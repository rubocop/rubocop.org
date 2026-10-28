# frozen_string_literal: true

require 'bridgetown'
require 'rubocop'
require 'tmpdir'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/cops'
require_relative '../../plugins/builders/examples'

RSpec.describe Builders::Examples do
  subject(:builder) { described_class.allocate }

  def example(name)
    Dir.mktmpdir { |dir| builder.send(:example, RuboCop::Cop::Registry.global.find_by_cop_name(name), dir) }&.last
  end

  it 'takes the first example from the docs' do
    expect(example('Style/NilComparison')).to include(code: start_with("# bad\nif x == nil\nend\n\n# good\n"),
                                                      file: 'example.rb')
  end

  it 'turns on just its cop, with the setting the example is titled with' do
    expect(YAML.safe_load(example('Style/NilComparison')[:config])).to eq(
      'AllCops' => { 'DisabledByDefault' => true, 'TargetRubyVersion' => 3.4 },
      'Style/NilComparison' => { 'Enabled' => true, 'EnforcedStyle' => 'predicate' }
    )
  end

  it 'names the file after what the cop looks at' do
    expect(example('Bundler/OrderedGems')[:file]).to eq('Gemfile')
  end

  it 'leaves out an example the cop finds nothing in' do
    expect(example('Layout/LineLength')).to be_nil
  end

  it "checks the examples against RuboCop's own defaults, as the playground runs without the plugins" do
    Builders::Cops.allocate.send(:default_config)

    builder.send(:with_core_defaults) do
      expect(RuboCop::ConfigLoader.default_configuration.for_all_cops['ActiveSupportExtensionsEnabled']).to be(false)
    end
  end

  it "leaves out the plugins' cops, which the playground doesn't load" do
    require 'rubocop-performance'

    expect(builder.send(:core_cops).map(&:department).uniq).not_to include(:Performance)
  end
end
