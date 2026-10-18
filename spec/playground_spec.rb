# frozen_string_literal: true

require 'open3'
require 'socket' # so the prelude keeps the real one
require 'tmpdir'
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

  # ruby.wasm has neither socket nor io/wait, and some cops load them, like
  # Style/IpAddresses through resolv. Booting doesn't load those cops, so this
  # loads all of them, in a Ruby where requiring either one fails.
  describe 'the Socket stub' do
    let(:script) do
      <<~RUBY
        # Bundler loads RubyGems' copy of uri, which autoloads IPSocket from
        # socket. The playground loads the prelude before anything like that.
        Object.send(:remove_const, :IPSocket) if Object.autoload?(:IPSocket)
        require_relative 'plugins/rubocop_html'
        load 'frontend/javascript/playground/prelude.rb'
        RuboCop::Cop::Registry.global.cops
      RUBY
    end

    let(:root) { File.expand_path('..', __dir__) }

    # Yields a directory to put first on the load path, where socket and
    # io/wait fail to load.
    def without_socket
      Dir.mktmpdir do |dir|
        Dir.mkdir(File.join(dir, 'io'))
        %w[socket io/wait].each { |lib| File.write(File.join(dir, "#{lib}.rb"), "raise LoadError, 'no #{lib}'") }
        yield dir
      end
    end

    it 'lets every cop load without socket and io/wait' do
      without_socket do |dir|
        output, status = Open3.capture2e(RbConfig.ruby, '-I', dir, '-e', script, chdir: root)
        expect(status).to be_success, output
      end
    end
  end
end
