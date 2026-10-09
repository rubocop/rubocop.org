// The home page grid: one square per cop. Hovering a square or a department
// prints what it is underneath. The details come from /cops.json, fetched on
// the first hover, since most visits never need them.
import { escape, withCode } from "./html.js"

const STATUS = { enabled: "on by default", pending: "pending", disabled: "opt-in" }
const FIX = { safe: "autocorrects with -a", unsafe: "autocorrects with -A" }

export function setupCopGrid() {
  const grid = document.querySelector(".cops-grid")
  if (!grid) return

  const readout = grid.querySelector(".readout")
  const idle = readout.innerHTML
  let cops

  const describe = async (event) => {
    const cell = event.target.closest(".cells a")
    if (!cell) return
    cops ??= fetch(grid.dataset.src).then((response) => response.json()).then((list) => new Map(list.map((cop) => [cop.name, cop])))
    const cop = (await cops).get(cell.getAttribute("aria-label"))
    if (!cop || !cell.matches(":hover, :focus")) return
    readout.innerHTML = `<b>${escape(cop.name)}</b> &middot; ${STATUS[cop.status]} &middot; ${FIX[cop.autocorrect] ?? "reports only"} &middot; since ${escape(cop.added)}<br>${withCode(cop.description)}`
  }

  grid.addEventListener("mouseover", describe)
  grid.addEventListener("focusin", describe)
  grid.addEventListener("mouseleave", () => (readout.innerHTML = idle))
  grid.addEventListener("focusout", (event) => { if (!grid.contains(event.relatedTarget)) readout.innerHTML = idle })

  for (const row of grid.querySelectorAll(".dept")) {
    const name = row.querySelector(".dept-name a")
    const light = () => {
      grid.classList.add("dim")
      row.classList.add("lit")
      readout.innerHTML = `<b>${escape(row.dataset.name)}</b> &middot; ${row.querySelectorAll(".cells a").length} cops &middot; ${row.dataset.fixable} can autocorrect`
    }
    const unlight = () => {
      grid.classList.remove("dim")
      row.classList.remove("lit")
      readout.innerHTML = idle
    }
    name.addEventListener("mouseenter", light)
    name.addEventListener("focus", light)
    name.addEventListener("mouseleave", unlight)
    name.addEventListener("blur", unlight)
  }

  setupGridKeys(grid)
}

// Tabbing through hundreds of squares would take forever, so the squares are
// a single stop in the tab order and the arrow keys move between them. Up and
// down go to the nearest square on the line above or below, as drawn.
function setupGridKeys(grid) {
  const cells = [...grid.querySelectorAll(".cells a")]
  cells.forEach((cell, i) => (cell.tabIndex = i ? -1 : 0))

  // The squares are in reading order, so this walks past the rest of the
  // current line, then picks the closest square on the next one.
  const nearest = (i, step) => {
    const at = (j) => cells[j]?.getBoundingClientRect()
    const from = at(i)
    let j = i + step
    while (at(j)?.top === from.top) j += step
    let best
    for (const line = at(j)?.top; at(j) && at(j).top === line; j += step) {
      if (best === undefined || Math.abs(at(j).left - from.left) < Math.abs(at(best).left - from.left)) best = j
    }
    return cells[best]
  }

  const moves = {
    ArrowRight: (i) => cells[i + 1],
    ArrowLeft: (i) => cells[i - 1],
    ArrowDown: (i) => nearest(i, 1),
    ArrowUp: (i) => nearest(i, -1),
    Home: () => cells[0],
    End: () => cells.at(-1),
  }

  grid.addEventListener("keydown", (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey) return
    const cell = moves[event.key] && event.target.closest(".cells a")
    if (!cell) return
    const next = moves[event.key](cells.indexOf(cell))
    if (!next) return
    event.preventDefault()
    cell.tabIndex = -1
    next.tabIndex = 0
    next.focus()
  })
}
