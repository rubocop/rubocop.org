# frozen_string_literal: true

require 'cgi/escape'

# Renders what RuboCop prints as HTML: ANSI colors become classes, the --diff
# patch gets colored and cop names link to their docs. The builders use it at
# build time, and the playground evaluates this same file inside ruby.wasm, so
# it sticks to the standard library.
module RubocopHTML
  DOCS_URL = 'https://docs.rubocop.org'

  # Docs components that are published without versions (no /latest/).
  UNVERSIONED_DOCS = %w[rubocop-thread_safety].freeze

  # The colors RuboCop uses. Bold stacks with them; a new color replaces the
  # current one.
  COLORS = { '2' => 't-d', '31' => 't-r', '32' => 't-g', '33' => 't-y', '35' => 't-m', '36' => 't-c' }.freeze

  DIFF_CLASSES = [[/\A(---|\+\+\+) /, 't-d'], [/\A@@/, 'hunk'], [/\A\+/, 'add'], [/\A-/, 'del']].freeze

  COP_NAME = %r{\b[A-Z][A-Za-z]*(?:/[A-Z][A-Za-z0-9]*)+\b}

  module_function

  # Docs anchors keep digits (Lint/UselessRuby2Keywords), so this doesn't use
  # RuboCop::Cop::Documentation, which drops them.
  def docs_url(cop_name, plugin = 'rubocop')
    department = cop_name.split('/')[0..-2].join('/')
    "#{department_url(department, plugin)}##{cop_name.downcase.gsub(/[^a-z0-9]/, '')}"
  end

  def department_url(department, plugin = 'rubocop')
    version = UNVERSIONED_DOCS.include?(plugin) ? '' : '/latest'
    "#{DOCS_URL}/#{plugin}#{version}/cops_#{department.downcase.tr('/', '_')}.html"
  end

  # Formatter output, then the patch if there is one. The block maps a cop
  # name to its docs URL, or nil to leave the name alone. With locations,
  # "file:line:col" positions become spans the playground can jump to.
  def terminal(text, locations: false, &)
    report, patch = text.split(%r{(?=^--- a/)}, 2)
    ansi(report.to_s, locations:, &) + (patch ? diff(patch) : '')
  end

  def ansi(text, locations: false, &)
    active = []
    html = text.split(/(\e\[[\d;]*m)/).map do |part|
      codes = part[/\A\e\[([\d;]*)m\z/, 1]
      next plain(part, locations:, &) unless codes

      closing = '</span>' * active.size
      active = apply(active, codes)
      closing + spans(active)
    end
    html.join + ('</span>' * active.size)
  end

  def spans(classes)
    classes.map { |css| %(<span class="#{css}">) }.join
  end

  def diff(patch)
    patch.lines(chomp: true).map do |line|
      css = DIFF_CLASSES.find { |pattern, _| pattern.match?(line) }&.last
      text = CGI.escapeHTML(line)
      css ? %(<span class="#{css}">#{text}</span>) : text
    end.join("\n")
  end

  # The classes in effect after an SGR sequence like "1;31".
  def apply(classes, codes)
    codes.split(';', -1).reduce(classes) { |current, code| sgr(current, code) }
  end

  # The classes in effect after one SGR code, the way a terminal tracks them.
  def sgr(classes, code)
    case code
    when '', '0' then []
    when '1' then classes | ['b']
    when '22' then classes - ['b']
    when '39' then classes - COLORS.values
    else COLORS.key?(code) ? (classes - COLORS.values) + [COLORS[code]] : classes
    end
  end

  # Text between color codes. A location follows the file name, which has a
  # color of its own, so it starts its part.
  def plain(text, locations: false, &link)
    html = CGI.escapeHTML(text)
    html = html.sub(/\A:(\d+):(\d+)(?=: )/, ':<span class="loc" data-line="\1" data-col="\2">\1:\2</span>') if locations
    return html unless link

    html.gsub(COP_NAME) do |name|
      url = link.call(name)
      url ? %(<a href="#{url}">#{name}</a>) : name
    end
  end
end
