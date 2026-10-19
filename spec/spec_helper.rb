# frozen_string_literal: true

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

# A builder whose site is this repository, for the builders that read the
# demo.
RSpec.shared_context 'with the repository as the site' do
  subject(:builder) do
    root = File.expand_path('..', __dir__)
    site = Struct.new(:root) { def in_root_dir(*parts) = File.join(root, *parts) }.new(root)
    described_class.allocate.tap { |builder| builder.define_singleton_method(:site) { site } }
  end
end
