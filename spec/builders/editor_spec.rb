# frozen_string_literal: true

require 'bridgetown'
require_relative '../../plugins/site_builder'
require_relative '../../plugins/builders/demo'
require_relative '../../plugins/builders/editor'

RSpec.describe Builders::Editor do
  include_context 'with the repository as the site'

  def cops(lines)
    lines.flat_map { |line| line[:segments].filter_map(&:last) }.map { |diagnostic| diagnostic[:cop] }
  end

  it 'leaves out a diagnostic that overlaps one before it' do
    first = { from: 0, to: 5 }
    segments = builder.send(:segments, 'value = 1', [first, { from: 2, to: 7 }])
    expect(segments).to eq([['', nil], ['value', first], [' = 1', nil]])
  end

  # One session, since each starts a language server.
  it 'opens the demo file and saves it the way an editor does', :aggregate_failures do
    session = builder.send(:session)
    line = session[:typing].find { |entry| entry[:open] }

    expect(line[:open]).to include(cop: described_class::OPEN, fixes: include("Autocorrect #{described_class::OPEN}"))
    expect(line[:segments].select(&:last).map(&:first)).to eq(['"stranger"'])
    expect(cops(session[:saved])).to eq(cops(session[:typing]) & ['Naming/MethodName'])
  end
end
