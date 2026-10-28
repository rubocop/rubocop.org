#!/usr/bin/env node
// Opens the built site in headless Chrome and checks what the specs can't
// see: every page fits a phone, loads without errors and passes axe in both
// themes, the keyboard gets around the tabs and the cop grid, the cop filters
// filter, and the playground runs RuboCop, on a cop's example from the cop
// index and with every cop turned on.
//
//   bin/check-pages.js [dir]   (output/ by default)

import axe from "axe-core"
import { shareHash } from "../frontend/javascript/playground/share.js"
import { BASE, Browser, serve } from "./chrome.js"

const ROOT = process.argv[2] ?? "output"
const PAGES = ["", "cops/", "playground/", "404.html"]
const WIDTHS = [1280, 768, 390, 320]
// How long the playground gets to download Ruby and RuboCop and run them.
const BOOT = 180_000

const problems = []
const report = (where, message) => problems.push(`${where}: ${message}`)

// The elements that stick out past the right edge of the page, outermost
// first, leaving out the ones inside something that scrolls or clips.
function overflowing() {
  const out = (element) => element.getBoundingClientRect().right > innerWidth + 1
  const clipped = (element) => {
    for (let parent = element.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
      if (getComputedStyle(parent).overflowX !== "visible") return true
    }
    return false
  }
  const name = (element) => element.tagName.toLowerCase() + (element.id ? `#${element.id}` : "") +
    [...element.classList].map((name) => `.${name}`).join("")
  return [...document.body.querySelectorAll("*")]
    .filter((element) => out(element) && !out(element.parentElement) && !clipped(element))
    .slice(0, 3).map(name)
}

const AXE = `${axe.source}
  axe.run({ resultTypes: ["violations"] }).then(({ violations }) =>
    violations.map(({ id, help, nodes }) => \`\${id} (\${help}): \${nodes.map((node) => node.target.join(" ")).join(", ")}\`))`

async function checkPages(browser, site) {
  for (const path of PAGES) {
    const where = `/${path}`
    const page = await browser.open(site + path)
    // Content that skips rendering until it's on screen clips whatever sticks
    // out of it, and axe can't see its colors.
    await page.evaluate(`document.head.insertAdjacentHTML("beforeend", "<style>* { content-visibility: visible !important }</style>")`)
    for (const theme of ["light", "dark"]) {
      await page.evaluate(`document.documentElement.dataset.theme = "${theme}"`)
      for (const violation of await page.evaluate(AXE)) report(`${where} in the ${theme} theme`, violation)
    }
    for (const width of WIDTHS) {
      await page.resize(width)
      const wide = await page.evaluate("document.documentElement.scrollWidth")
      if (wide > width) report(`${where} at ${width}px`, `${wide}px wide because of ${await page.evaluate(`(${overflowing})()`)}`)
    }
    for (const error of page.errors) report(where, error)
    await page.close()
  }
}

async function checkKeyboard(browser, site) {
  const page = await browser.open(site)

  await page.evaluate(`document.querySelector(".hero .term [role=tab]").focus()`)
  await page.press("ArrowRight")
  const tab = await page.evaluate(`(() => {
    const tab = document.activeElement
    const panels = [...tab.closest("[role=tablist]").querySelectorAll("[role=tab]")].map((tab) => document.getElementById(tab.getAttribute("aria-controls")))
    return { name: tab.textContent.trim(), selected: tab.ariaSelected, shown: panels.filter((panel) => !panel.hidden).map((panel) => panel.id) }
  })()`)
  if (tab.name !== "rubocop --diff" || tab.selected !== "true" || tab.shown.length !== 1) {
    report("/ hero tabs", `ArrowRight should select and show "rubocop --diff", got ${JSON.stringify(tab)}`)
  }

  await page.evaluate(`document.querySelector(".cops-grid .cells a").focus()`)
  await page.press("ArrowRight")
  const second = await page.evaluate(`document.querySelectorAll(".cops-grid .cells a")[1].getAttribute("aria-label")`)
  if (!await page.waitFor(`document.querySelector(".cops-grid .readout").textContent.startsWith(${JSON.stringify(second)})`)) {
    report("/ cop grid", `ArrowRight should move to ${second} and describe it`)
  }

  await page.close()
}

async function checkCopFilters(browser, site) {
  const cases = [
    ["q=Style/StringLiterals", 2, `row.querySelector(".name").textContent.startsWith("Style/StringLiterals")`],
    ["q=Style/*Literal*", 2, `/^Style\\/.*Literal/.test(row.querySelector(".name").textContent)`],
    ["status=pending&fix=none", 1, `row.dataset.status === "pending" && row.dataset.fix === "none"`],
    ["index=yes", 1, `row.dataset.index === "yes"`],
    ["since=1.80", 1, `row.closest(".dept-group").dataset.plugin === "rubocop" && newer(row, 1, 80)`],
    ["department=Rails&since=2.30", 1, `row.closest(".dept-group").dataset.plugin === "rubocop-rails" && newer(row, 2, 30)`],
  ]
  for (const [query, least, test] of cases) {
    const page = await browser.open(`${site}cops/?${query}`)
    const shown = `(() => {
      const newer = (row, major, minor) => {
        const [a, b] = row.querySelector(".since").textContent.split(".").map(Number)
        return a > major || (a === major && b > minor)
      }
      const rows = [...document.querySelectorAll(".cop-list li:not([hidden])")]
      return rows.length >= ${least} && rows.every((row) => ${test})
    })()`
    if (!await page.waitFor(shown)) report(`/cops/?${query}`, "shows the wrong cops")
    await page.close()
  }
}

// A cop's example, linked from the cop index, then the default example with
// every cop on, which loads the cops that only require what they need once
// they're enabled.
async function checkPlayground(browser, site) {
  const playground = `${site}playground/`
  const runs = [
    ["Bundler/OrderedGems's example", `${playground}#cop=Bundler/OrderedGems`, /^Gemfile:\d+:\d+: .*Bundler\/OrderedGems:/m],
    ["every cop", `${playground}#${await shareHash({ config: "AllCops:\n  EnabledByDefault: true\n" })}`, /Style\/Copyright:/],
  ]
  for (const [what, url, expected] of runs) {
    const page = await browser.open(url)
    await page.waitFor(`/ ms$|failed|not running/.test(document.getElementById("state").textContent)`, BOOT)
    const { state, output } = await page.evaluate(`({ state: document.getElementById("state").textContent, output: document.getElementById("output").textContent })`)
    if (!/ ms$/.test(state) || !expected.test(output) || /error occurred/i.test(output)) {
      report(`/playground/ with ${what}`, `${state}\n${output}`)
    }
    await page.close()
  }
}

const server = await serve(ROOT)
const site = `http://127.0.0.1:${server.address().port}${BASE}`
const browser = await Browser.launch()
try {
  for (const check of [checkPages, checkKeyboard, checkCopFilters, checkPlayground]) {
    await check(browser, site).catch((error) => report(check.name, error.message))
  }
} finally {
  await browser.close()
  server.close()
}

for (const problem of problems) console.log(problem)
console.log(problems.length ? `\n${problems.length} problem${problems.length === 1 ? "" : "s"} found` : "All pages check out")
process.exitCode = problems.length ? 1 : 0
