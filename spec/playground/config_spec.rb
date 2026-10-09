# frozen_string_literal: true

require 'erb'
require 'socket' # so the prelude keeps the real one
require_relative '../../plugins/rubocop_html'
load File.expand_path('../../frontend/javascript/playground/prelude.rb', __dir__)

RSpec.describe Playground::Config do
  describe '.build' do
    # What RuboCop's ConfigLoader does with the file: ERB, then YAML.
    def load_like_rubocop(yaml)
      YAML.safe_load(ERB.new(yaml).result, permitted_classes: [Regexp, Symbol], aliases: true)
    end

    it 'drops keys that would load code from outside, with a note for each', :aggregate_failures do
      yaml, notes, = described_class.build("require: rubocop-rails\nplugins: [x]\nStyle/Foo:\n  Enabled: true\n")

      expect(load_like_rubocop(yaml).keys).to contain_exactly('AllCops', 'Style/Foo')
      expect(notes).to eq(['require: is ignored in the playground', 'plugins: is ignored in the playground'])
    end

    it 'refuses ERB' do
      expect { described_class.build("AllCops:\n  Foo: <%= `id` %>\n") }.to raise_error(ArgumentError, /ERB/)
    end

    it 'keeps ERB that YAML escapes from running when RuboCop loads the file' do
      yaml, = described_class.build(%(Style/Foo:\n  Note: "\\x3C%= raise 'ran' %>"\n))

      expect(load_like_rubocop(yaml).dig('Style/Foo', 'Note')).to eq("<%= raise 'ran' %>")
    end

    it 'turns off what the playground has no use for' do
      yaml, = described_class.build('')

      expect(load_like_rubocop(yaml)['AllCops']).to include('SuggestExtensions' => false, 'UseCache' => false)
    end

    it 'keeps pending cops off without the long notice when NewCops is not set', :aggregate_failures do
      expect(described_class.build('').last).to eq(['--disable-pending-cops'])
      expect(described_class.build("AllCops:\n  NewCops: enable\n").last).to eq([])
    end

    it 'refuses a config that is not a mapping' do
      expect { described_class.build("- a\n- b\n") }.to raise_error(ArgumentError, /mapping/)
    end
  end
end
