# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/demo_runs'
require_relative '../../plugins/builders/walkthrough'

RSpec.describe Builders::Walkthrough do
  subject(:builder) do
    root = File.expand_path('../..', __dir__)
    site = Struct.new(:root) { def in_root_dir(*parts) = File.join(root, *parts) }.new(root)
    described_class.allocate.tap { |builder| builder.define_singleton_method(:site) { site } }
  end

  # The parts the match step picks out.
  let(:marked) { builder.send(:match).scan(/\e\[1;33m(.*?)\e\[22;2m/m).flatten }

  it 'shows the file, then its tree' do
    expect(builder.send(:parse)).to include("return if user == nil\n\n\e[2m# the tree RuboCop inspects\e[0m\n(if\n")
  end

  it 'marks the pattern in the line of the cop that defines it' do
    expect(marked.first).to match(/\A'\(send .*\)'\z/)
  end

  it 'marks the node the pattern matches in the tree' do
    expect(marked.last).to eq("(send\n    (send nil :user) :==\n    (nil))")
  end
end
