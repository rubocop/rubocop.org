# frozen_string_literal: true

require 'socket' # so the prelude keeps the real one
require_relative '../plugins/rubocop_html'
load File.expand_path('../frontend/javascript/playground/prelude.rb', __dir__)

RSpec.describe Playground do
  describe 'FILE_NAME' do
    let(:fine) { %w[example.rb Gemfile foo.gemspec a_b-c.rb] }
    let(:refused) { %w[-a --lint .rubocop.yml ../etc a/b] }

    it 'allows ordinary file names' do
      expect(fine).to all(match(described_class::FILE_NAME))
    end

    it 'rejects names that would be options, hidden files or paths' do
      expect(refused).to all(satisfy { |name| !described_class::FILE_NAME.match?(name) })
    end
  end
end
