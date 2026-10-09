# frozen_string_literal: true

require_relative '../plugins/rubocop_html'

RSpec.describe RubocopHTML do
  describe '.docs_url' do
    it 'links a core cop to the latest docs' do
      expect(described_class.docs_url('Style/StringLiterals'))
        .to eq('https://docs.rubocop.org/rubocop/latest/cops_style.html#stylestringliterals')
    end

    it 'keeps digits in the anchor' do
      expect(described_class.docs_url('Lint/UselessRuby2Keywords')).to end_with('#lintuselessruby2keywords')
    end

    it 'handles nested departments' do
      expect(described_class.docs_url('Capybara/RSpec/HaveSelector', 'rubocop-capybara'))
        .to eq('https://docs.rubocop.org/rubocop-capybara/latest/cops_capybara_rspec.html#capybararspechaveselector')
    end

    it 'leaves the version out for unversioned docs' do
      expect(described_class.docs_url('ThreadSafety/MutableClassInstanceVariable', 'rubocop-thread_safety'))
        .to start_with('https://docs.rubocop.org/rubocop-thread_safety/cops_threadsafety.html#')
    end
  end

  describe '.ansi' do
    it 'turns colors into classes and escapes the text' do
      expect(described_class.ansi("\e[33mC\e[0m: <x>")).to eq('<span class="t-y">C</span>: &lt;x&gt;')
    end

    it 'stacks bold with a color, the way a terminal does' do
      expect(described_class.ansi("\e[1m\e[31mbold red\e[0m"))
        .to end_with('<span class="b"><span class="t-r">bold red</span></span>')
    end

    it 'lets a new color replace the current one' do
      expect(described_class.ansi("\e[31ma\e[32mb\e[0m")).to eq('<span class="t-r">a</span><span class="t-g">b</span>')
    end

    it 'links the cop names the block knows' do
      html = described_class.ansi('Style/Foo: and Not/ACop:') { |name| "/#{name}" if name == 'Style/Foo' }

      expect(html).to eq('<a href="/Style/Foo">Style/Foo</a>: and Not/ACop:')
    end

    it 'marks locations after a colored file name' do
      html = described_class.ansi("\e[36mexample.rb\e[0m:3:5: C: msg", locations: true)

      expect(html).to include(':<span class="loc" data-line="3" data-col="5">3:5</span>: C: msg')
    end
  end

  describe '.terminal' do
    it 'colors the --diff patch after the report' do
      html = described_class.terminal("1 file inspected\n--- a/x.rb\n+++ b/x.rb\n@@ -1 +1 @@\n-old\n+new\n same")

      expect(html.lines(chomp: true)).to eq(
        [
          '1 file inspected',
          '<span class="t-d">--- a/x.rb</span>',
          '<span class="t-d">+++ b/x.rb</span>',
          '<span class="hunk">@@ -1 +1 @@</span>',
          '<span class="del">-old</span>',
          '<span class="add">+new</span>',
          ' same'
        ]
      )
    end

    it 'leaves output without a patch alone' do
      expect(described_class.terminal("--\n5  Total in 2 files")).to eq("--\n5  Total in 2 files")
    end
  end
end
