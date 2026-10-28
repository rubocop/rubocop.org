# frozen_string_literal: true

require 'cgi/escape'

module Builders
  # Helpers for the templates.
  class Helpers < SiteBuilder
    include Streamlined::Helpers

    STATUS = { 'enabled' => 'on', 'pending' => 'pending', 'disabled' => 'opt-in' }.freeze
    FIX = {
      'safe' => ['-a', 'Fixed by rubocop -a'],
      'unsafe' => ['-A', 'Fixed by rubocop -A, which may change behavior']
    }.freeze
    NEWS_ITEMS = 6
    NUMBERS = %w[
      zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen
      seventeen eighteen nineteen twenty
    ].freeze

    def build
      %i[
        page_title code_spans delimited in_words years_since cop_link status_label fix_badge terminal terminal_tabs
        editor_tabs news latest_release release_post
      ].each do |name|
        helper name
      end
    end

    # "Cops | RuboCop", or the tagline on the home page. Bridgetown would title
    # that one "Index" after its file name, so it sets an empty title instead.
    def page_title(title)
      return "#{site.metadata.title}: #{site.metadata.tagline}" if title.to_s.empty?

      "#{title} | #{site.metadata.title}"
    end

    # Escapes text and turns `backticks` into <code>, the way RuboCop's
    # messages and the release notes mark up code.
    def code_spans(text)
      CGI.escapeHTML(text.to_s).gsub(/`([^`]+)`/, '<code>\1</code>').html_safe
    end

    # 1019 -> "1,019"
    def delimited(number)
      number.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
    end

    # 14 -> "fourteen". Past twenty it's digits.
    def in_words(number)
      NUMBERS.fetch(number, number.to_s)
    end

    # Whole years from the date until today.
    def years_since(date)
      today = Date.today
      today.year - date.year - (today.strftime('%m%d') < date.strftime('%m%d') ? 1 : 0)
    end

    def cop_link(name)
      url = site.data.cop_urls[name]
      (url ? %(<a href="#{url}">#{CGI.escapeHTML(name)}</a>) : CGI.escapeHTML(name)).html_safe
    end

    def status_label(status) = STATUS.fetch(status)

    def fix_badge(fix)
      label, title = FIX[fix]
      return '<span class="fx none" aria-hidden="true">-a</span>'.html_safe unless label

      %(<span class="fx #{fix}" title="#{title}">#{label}</span>).html_safe
    end

    # A recorded run from the demo project: the prompt, then its output.
    # Output without a command, like the walkthrough's tree, gets no prompt.
    # The attributes go on the <pre>.
    def terminal(run, **attributes)
      html = RubocopHTML.terminal(run[:output]) { |name| site.data.cop_urls[name] }
      if run[:command]
        html = %(<span class="pr">~/shop $ </span><span class="cmd">#{CGI.escapeHTML(run[:command])}</span>\n#{html})
      end
      "<pre#{html_attributes(attributes, prefix_space: true)}>#{html}</pre>".html_safe
    end

    # Several runs behind tabs, the first one showing. Keys are tab labels.
    def terminal_tabs(prefix, runs)
      tabs(prefix, runs) { |run, **attributes| terminal(run, **attributes) }
    end

    # A file the way an editor running the language server shows it, a state
    # of it per tab: its diagnostics underlined, and one of them opened up
    # under its line with its quick fixes. Editor lays the lines out.
    def editor_tabs(prefix, states)
      tabs(prefix, states) { |state, **attributes| editor(state, **attributes) }
    end

    # The latest releases and Meta Redux posts, newest first.
    def news
      releases = site.data.releases.map { |release| release.merge(kind: 'release') }
      (releases + site.data.posts).sort_by { |item| item[:date] }.reverse.first(NEWS_ITEMS)
    end

    # The newest release on GitHub, skipping prereleases. GitHub lists them by
    # date, so a backport can come after a newer release. This can be ahead of
    # the bundled RuboCop (site.data.rubocop.version) until Gemfile.lock
    # catches up.
    def latest_release
      site.data.releases.reject { |release| release[:prerelease] }.max_by { |release| Gem::Version.new(release[:version]) }
    end

    # The Meta Redux write-up for a release, if there is one. Its address ends
    # in rubocop-1-91.html for 1.91.x.
    def release_post(release)
      slug = "rubocop-#{release[:version][/\A\d+\.\d+/].tr('.', '-')}"
      site.data.posts.find { |post| post[:url].match?(%r{/#{slug}(?:\.html)?\z}) }
    end

    private

    # Panes behind tabs, the first one showing. Keys are tab labels, and the
    # block renders a pane with the attributes it's given.
    def tabs(prefix, panes)
      buttons, html = panes.each_with_index.map do |(label, pane), i|
        tab = "#{prefix}-tab-#{i}"
        id = "#{prefix}-#{i}"
        button = { type: 'button', role: 'tab', id: tab, aria_selected: i.zero?.to_s, aria_controls: id }
        [
          "<button#{html_attributes(button, prefix_space: true)}>#{label}</button>",
          yield(pane, id:, role: 'tabpanel', aria_labelledby: tab, tabindex: 0, hidden: !i.zero?)
        ]
      end.transpose
      %(<div class="term-tabs" role="tablist">#{buttons.join}</div>#{html.join}).html_safe
    end

    def editor(lines, **attributes)
      html = lines.each_with_index.map do |line, i|
        code = line[:segments].map { |text, diagnostic| diagnostic ? squiggle(text, diagnostic) : CGI.escapeHTML(text) }
        %(<span class="ln"><span class="gutter">#{i + 1}</span>#{code.join}</span>#{peek(line[:open]) if line[:open]})
      end
      "<pre#{html_attributes(attributes, prefix_space: true)}>#{html.join}</pre>".html_safe
    end

    # Underlined, with the message on hover and for screen readers.
    def squiggle(text, diagnostic)
      message = CGI.escapeHTML(diagnostic[:message])
      %(<span class="squiggle s#{diagnostic[:severity]}" title="#{message}">#{CGI.escapeHTML(text)}</span>) +
        %(<span class="sr-only"> (#{message})</span>)
    end

    # A diagnostic spelled out, the way an editor shows it on hover, with the
    # quick fixes the server offers for it.
    def peek(diagnostic)
      fixes = diagnostic[:fixes].map { |fix| %(<span class="fix">#{CGI.escapeHTML(fix)}</span>) }
      %(<span class="peek s#{diagnostic[:severity]}">#{code_spans(diagnostic[:message])}) +
        %(<span class="via">RuboCop(#{cop_link(diagnostic[:cop])})</span>#{fixes.join}</span>)
    end
  end
end
