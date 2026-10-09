# frozen_string_literal: true

# tokens.css promises 4.5:1 contrast for text (WCAG AA), in both themes. This
# keeps a new or tweaked color from quietly breaking that.
RSpec.describe 'frontend/styles/tokens.css' do # rubocop:disable RSpec/DescribeClass -- a stylesheet, not a class
  # name => [light, dark]
  let(:tokens) do
    File.read(File.expand_path('../frontend/styles/tokens.css', __dir__))
        .scan(/--([\w-]+):\s*(?:light-dark\((#\h{6}),\s*(#\h{6})\)|(#\h{6}));/)
        .to_h { |name, light, dark, both| [name, [light || both, dark || both]] }
  end

  def contrast(*colors)
    high, low = colors.map { luminance(it) }.sort.reverse
    (high + 0.05) / (low + 0.05)
  end

  def luminance(hex)
    red, green, blue = hex.delete('#').scan(/../).map do |channel|
      value = channel.to_i(16) / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  {
    %w[paper paper-2] => %w[ink ink-2 ink-3 red-text ok yaml-value hash magenta-text],
    %w[term] => %w[term-ink term-dim t-yellow t-magenta t-red t-green t-cyan t-add t-del]
  }.each do |backgrounds, texts|
    texts.product(backgrounds).each do |text, background|
      it "keeps --#{text} readable on --#{background}" do
        tokens.fetch(text).zip(tokens.fetch(background)).each do |ink, paper|
          expect(contrast(ink, paper)).to be >= 4.5, "#{ink} on #{paper} is #{contrast(ink, paper).round(2)}:1"
        end
      end
    end
  end
end
