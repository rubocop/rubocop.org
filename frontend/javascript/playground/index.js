// The playground page: two CodeMirror editors (the code and its
// .rubocop.yml) and RuboCop's own output, produced by worker.js.
import { EditorState, StateEffect, StateField, RangeSet } from "@codemirror/state"
import { EditorView, GutterMarker, gutter, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter, drawSelection } from "@codemirror/view"
import { defaultKeymap, history as undoHistory, historyKeymap, indentWithTab } from "@codemirror/commands"
import { StreamLanguage, syntaxHighlighting, indentUnit } from "@codemirror/language"
import { classHighlighter } from "@lezer/highlight"
import { setDiagnostics } from "@codemirror/lint"
import { ruby } from "@codemirror/legacy-modes/mode/ruby"
import { yaml } from "@codemirror/legacy-modes/mode/yaml"
import { selectTab } from "../site/tabs.js"
import { escape, withCode } from "../site/html.js"
import { readShared, shareLink } from "./share.js"

const EXAMPLE = `class Greeter
  def initialize(name)
    @name = name
  end

  def greet(punctuation = "!")
    if @name == nil then return "Hello, stranger" end
    greeting = "Hello"
    return "Hello, #{@name}" + punctuation
  end
end
`
const EXAMPLE_CONFIG = `# require, plugins and inherit_* are ignored here.
AllCops:
  TargetRubyVersion: 3.4
  NewCops: enable
`

// RuboCop's severities, least severe first, as CodeMirror's.
const SEVERITIES = {
  info: ["I", "hint"],
  refactor: ["R", "hint"],
  convention: ["C", "info"],
  warning: ["W", "warning"],
  error: ["E", "error"],
  fatal: ["F", "error"],
}
const RANK = Object.keys(SEVERITIES)

const page = document.getElementById("playground")
const output = document.getElementById("output")
const state = document.getElementById("state")
const announcer = document.getElementById("announce")
const fileInput = document.getElementById("file")
const applyButton = document.getElementById("apply")

const fileName = () => (/^\w[\w.-]{0,63}$/.test(fileInput.value) ? fileInput.value : "example.rb")

let mode = "lint"
let rubyVersion = page.dataset.ruby
let code, config

// --- the editors, styled with the site's tokens -----------------------------

const theme = EditorView.theme({
  "&": { height: "100%", backgroundColor: "var(--paper)", color: "var(--ink)", fontSize: "13.5px" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: "var(--mono)", fontStretch: "87.5%", lineHeight: "1.65" },
  ".cm-content": { padding: ".8rem 0", caretColor: "var(--red)" },
  ".cm-cursor, .cm-dropCursor": { borderLeft: "2px solid var(--red)" },
  ".cm-gutters": { backgroundColor: "var(--paper)", color: "var(--ink-3)", borderRight: "1px solid var(--rule)" },
  ".cm-lineNumbers .cm-gutterElement": { minWidth: "2.5rem", padding: "0 .7rem 0 .9rem" },
  ".cm-activeLine, .cm-activeLineGutter": { backgroundColor: "color-mix(in srgb, var(--paper-2) 70%, transparent)" },
  "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection": {
    backgroundColor: "color-mix(in srgb, var(--red) 22%, transparent)",
  },
  // Offenses get red underlines: warnings and errors in full, conventions a
  // little lighter, refactorings lighter still.
  ".cm-lintRange": {
    backgroundImage: "none",
    textDecoration: "underline wavy color-mix(in srgb, var(--red) 55%, transparent)",
    textDecorationSkipInk: "none",
    textUnderlineOffset: "3px",
  },
  ".cm-lintRange-hint": { textDecorationColor: "color-mix(in srgb, var(--red) 35%, transparent)" },
  ".cm-lintRange-warning, .cm-lintRange-error": { textDecorationColor: "var(--red)" },
  ".cm-severity .cm-gutterElement": { width: "1.6em", paddingLeft: ".4rem", textAlign: "center", fontWeight: "700", fontSize: "11px" },
  ".sev-C": { color: "var(--hash)" },
  ".sev-W": { color: "var(--magenta-text)" },
  ".sev-E, .sev-F": { color: "var(--red-text)" },
  ".sev-R, .sev-I": { color: "var(--ink-3)" },
  ".cm-tooltip": {
    maxWidth: "34rem",
    backgroundColor: "var(--term)",
    color: "var(--term-ink)",
    border: "1px solid var(--term-edge)",
    borderRadius: "4px",
    font: "400 12.5px/1.55 var(--mono)",
    fontStretch: "87.5%",
  },
  ".cm-tooltip.cm-tooltip-lint": { padding: "0" },
  ".cm-diagnostic": { padding: ".45rem .7rem", borderLeft: "3px solid var(--red)" },
  ".cm-diagnostic a": { color: "var(--t-cyan)" },
})

// The gutter shows each line's worst offense the way RuboCop prints it: C, W, E...
class SeverityMarker extends GutterMarker {
  constructor(letter) {
    super()
    this.letter = letter
  }

  eq(other) { return other.letter === this.letter }

  toDOM() {
    const element = document.createElement("span")
    element.className = `sev-${this.letter}`
    element.textContent = this.letter
    return element
  }
}

const setSeverities = StateEffect.define()
const severities = StateField.define({
  create: () => RangeSet.empty,
  update(markers, transaction) {
    for (const effect of transaction.effects) if (effect.is(setSeverities)) return effect.value
    return markers.map(transaction.changes)
  },
})

function severityMarkers(offenses, doc) {
  const worst = new Map()
  for (const { severity, location } of offenses) {
    const line = Math.min(location.start_line, doc.lines)
    if (RANK.indexOf(severity) > RANK.indexOf(worst.get(line))) worst.set(line, severity)
  }
  const markers = [...worst].sort(([a], [b]) => a - b)
    .map(([line, severity]) => new SeverityMarker(SEVERITIES[severity][0]).range(doc.line(line).from))
  return RangeSet.of(markers)
}

function diagnostics(offenses, doc) {
  return offenses.map(({ severity, message, cop_name: cop, url, location: at }) => {
    const start = doc.line(Math.min(at.start_line, doc.lines))
    const end = doc.line(Math.min(at.last_line, doc.lines))
    const from = Math.min(start.from + at.start_column - 1, start.to)
    let to = Math.min(end.from + at.last_column, end.to)
    if (to <= from) to = Math.min(from + 1, doc.length)
    const text = message.startsWith(`${cop}: `) ? message.slice(cop.length + 2) : message
    return {
      from,
      to,
      severity: SEVERITIES[severity]?.[1] ?? "info",
      message: `${cop}: ${text}`,
      renderMessage: () => {
        const element = document.createElement("div")
        const name = url ? `<a href="${url}" target="_blank" rel="noopener">${escape(cop)}</a>` : escape(cop)
        element.innerHTML = `${name}: ${withCode(text, "t-y")}`
        return element
      },
    }
  })
}

function editor(parent, doc, language, label) {
  return new EditorView({
    parent,
    state: EditorState.create({
      doc,
      extensions: [
        theme,
        language === ruby ? [severities, gutter({ class: "cm-severity", markers: (view) => view.state.field(severities) })] : [],
        lineNumbers(), highlightActiveLine(), highlightActiveLineGutter(), drawSelection(), undoHistory(),
        indentUnit.of("  "), EditorState.tabSize.of(2),
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        StreamLanguage.define(language), syntaxHighlighting(classHighlighter),
        EditorView.updateListener.of((update) => { if (update.docChanged) schedule() }),
        EditorView.contentAttributes.of({ "aria-label": label, "aria-describedby": "editor-help" }),
      ],
    }),
  })
}

function replace(view, text) {
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } })
}

function showPane(id) {
  for (const tab of document.querySelectorAll(".src [data-pane]")) tab.setAttribute("aria-current", tab.dataset.pane === id)
  for (const pane of document.querySelectorAll(".src .editor")) pane.hidden = pane.id !== id
}

// The status line under the editors. Screen readers hear `spoken` instead,
// and only when it changes, so a run reads out its offense count rather than
// the timing or the whole output.
function setStatus(text, spoken = text) {
  state.textContent = text
  if (announcer.textContent !== spoken) announcer.textContent = spoken
}

function selectMode(next) {
  mode = next
  selectTab(document.querySelector(`.out [data-mode="${mode}"]`))
  schedule(0)
}

// --- the worker --------------------------------------------------------------

// A run that takes longer than this is stuck, or the input is enormous, so
// the worker gets replaced. By then the browser has the downloads cached.
const RUN_TIMEOUT = 20000
const TOO_SLOW = "RuboCop took too long on this input, so the playground restarted it."

const pending = new Map()
let worker
let nextId = 0
let ready = false

function startWorker() {
  ready = false
  worker = new Worker(page.dataset.worker)
  worker.onmessage = onMessage
  worker.onerror = (event) => fail(event.message || "the worker failed to start")
  worker.postMessage({
    type: "boot",
    runtime: { url: page.dataset.runtime, size: Number(page.dataset.runtimeSize) },
    gems: { url: page.dataset.gems, size: Number(page.dataset.gemsSize) },
  })
}

function onMessage({ data }) {
  if (data.type === "progress") {
    const bar = "=".repeat(Math.floor(data.percent / 4)).padEnd(25, " ")
    output.innerHTML = `<span class="pr">$ </span><span class="cmd">gem install rubocop</span>\n` +
      `Fetching Ruby ${escape(rubyVersion)} (wasm) and RuboCop\n` +
      `<span class="t-d">[</span><span class="t-g">${bar}</span><span class="t-d">]</span> ${data.percent}%`
  } else if (data.type === "status") {
    setStatus(`${data.text}...`)
  } else if (data.type === "ready") {
    ready = true
    rubyVersion = data.ruby
    setStatus(`RuboCop ${data.version} on Ruby ${rubyVersion} (wasm), ready in ${(data.ms / 1000).toFixed(1)}s`)
    schedule(0)
  } else if (pending.has(data.id)) {
    settle(data.id, data)
  } else if (data.type === "error") {
    fail(data.message)
  }
}

function settle(id, data) {
  const { resolve, timeout } = pending.get(id)
  clearTimeout(timeout)
  pending.delete(id)
  resolve(data)
}

// The input that got stuck isn't run again until it changes.
let stuck = ""

function restartWorker() {
  stuck = resultsFor
  worker.terminate()
  for (const id of [...pending.keys()]) settle(id, { type: "error", message: TOO_SLOW })
  startWorker()
}

function showOutput({ command, notes = [], html = "", errors = "" }) {
  const lines = [`<span class="pr">$ </span><span class="cmd">${escape(command ?? "rubocop")}</span>`]
  for (const note of notes) lines.push(`<span class="t-d"># ${escape(note)}</span>`)
  if (html) lines.push(html)
  if (errors) lines.push(`<span class="t-r">${errors}</span>`)
  output.innerHTML = lines.join("\n")
}

function showError(message) {
  showOutput({ command: `rubocop ${fileName()}`, errors: escape(message) })
  setStatus("RuboCop failed on this input")
}

function fail(message) {
  output.innerHTML = `<span class="t-r">Couldn't start RuboCop: ${escape(message)}</span>\n` +
    `<span class="t-d"># The playground needs WebAssembly and about 11 MB of downloads. Reloading usually helps.</span>`
  setStatus("not running")
}

function input() {
  return { file: fileName(), source: code.state.doc.toString(), config: config.state.doc.toString() }
}

// Results only change with the input, so switching tabs back and forth
// reuses them instead of running RuboCop again. Errors aren't kept.
let results = new Map()
let resultsFor = ""

function call(runMode) {
  const request = input()
  const key = JSON.stringify(request)
  if (key === stuck) return Promise.resolve({ type: "error", message: TOO_SLOW })
  if (key !== resultsFor) {
    results = new Map()
    resultsFor = key
  }
  if (runMode.startsWith("fix") || !results.has(runMode)) {
    const result = new Promise((resolve) => {
      const id = nextId++
      pending.set(id, { resolve, timeout: setTimeout(restartWorker, RUN_TIMEOUT) })
      worker.postMessage({ type: "run", id, mode: runMode, ...request })
    })
    result.then((data) => { if (data.type === "error" && results.get(runMode) === result) results.delete(runMode) })
    results.set(runMode, result)
  }
  return results.get(runMode)
}

// Edits come in bursts, so runs are debounced and never overlap.
let timer
let running = false
let again = false

function schedule(delay = 250) {
  clearTimeout(timer)
  timer = setTimeout(refresh, delay)
}

async function refresh() {
  if (!ready) return
  if (running) {
    again = true
    return
  }
  running = true
  try {
    // Offsets in a diff run point into intermediate versions of the code, so
    // the editor's underlines always come from a plain run.
    const sent = code.state.doc
    const lint = await call("lint")
    // Edited in the meantime: the offsets are stale and another run is due.
    if (!code.state.doc.eq(sent)) return
    if (lint.type === "error") return showError(lint.message)
    const offenses = lint.offenses ?? []
    code.dispatch(setDiagnostics(code.state, diagnostics(offenses, sent)), {
      effects: setSeverities.of(severityMarkers(offenses, sent)),
    })
    const shown = mode === "lint" ? lint : await call(mode)
    if (shown.type === "error") return showError(shown.message)
    showOutput(shown)
    applyButton.hidden = mode === "lint" || !shown.patch
    const count = offenses.length ? `${offenses.length} offense${offenses.length === 1 ? "" : "s"}` : "no offenses"
    setStatus(`RuboCop on Ruby ${rubyVersion} (wasm), ${shown.ms} ms`, count)
    saveDraft()
  } finally {
    running = false
    if (again) {
      again = false
      refresh()
    }
  }
}

// --- drafts and links ---------------------------------------------------------

function current() {
  const { file, source, config } = input()
  return { file, mode, code: source, config }
}

function saveDraft() {
  try { localStorage.setItem("playground", JSON.stringify(current())) } catch { /* storage blocked */ }
}

async function main() {
  const shared = await readShared(page.dataset.examples)
  code = editor(document.getElementById("ed-code"), shared?.code ?? EXAMPLE, ruby, "Ruby code")
  config = editor(document.getElementById("ed-config"), shared?.config ?? EXAMPLE_CONFIG, yaml, "RuboCop configuration")
  if (shared?.file) fileInput.value = shared.file
  if (["lint", "diff", "diff-all"].includes(shared?.mode)) mode = shared.mode

  for (const tab of document.querySelectorAll(".src [data-pane]")) tab.addEventListener("click", () => showPane(tab.dataset.pane))
  fileInput.addEventListener("focus", () => showPane("ed-code"))
  for (const tab of document.querySelectorAll(".out [data-mode]")) tab.addEventListener("click", () => selectMode(tab.dataset.mode))
  fileInput.addEventListener("input", () => schedule())

  document.getElementById("reset").addEventListener("click", () => {
    replace(code, EXAMPLE)
    replace(config, EXAMPLE_CONFIG)
    fileInput.value = "example.rb"
    history.replaceState(null, "", location.pathname)
  })

  applyButton.addEventListener("click", async () => {
    const fixed = await call(mode === "diff-all" ? "fix-all" : "fix")
    if (fixed.source != null) replace(code, fixed.source)
    selectMode("lint")
  })

  output.addEventListener("click", (event) => {
    const loc = event.target.closest(".loc")
    if (!loc) return
    showPane("ed-code")
    const line = code.state.doc.line(Math.min(Number(loc.dataset.line), code.state.doc.lines))
    code.dispatch({ selection: { anchor: Math.min(line.from + Number(loc.dataset.col) - 1, line.to) }, scrollIntoView: true })
    code.focus()
  })

  const share = document.getElementById("share")
  share.addEventListener("click", async () => {
    const url = await shareLink(current())
    history.replaceState(null, "", url)
    try {
      await navigator.clipboard.writeText(url)
      share.textContent = "link copied"
    } catch {
      share.textContent = "link in the address bar"
    }
    setTimeout(() => (share.textContent = "copy link"), 1600)
  })

  selectMode(mode)
}

startWorker()
main()
