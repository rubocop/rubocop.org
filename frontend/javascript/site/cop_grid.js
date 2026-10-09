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

  for (const row of grid.querySelectorAll(".dept")) {
    const name = row.querySelector(".dept-name a")
    name.addEventListener("mouseenter", () => {
      grid.classList.add("dim")
      row.classList.add("lit")
      readout.innerHTML = `<b>${escape(row.dataset.name)}</b> &middot; ${row.querySelectorAll(".cells a").length} cops &middot; ${row.dataset.fixable} can autocorrect`
    })
    name.addEventListener("mouseleave", () => {
      grid.classList.remove("dim")
      row.classList.remove("lit")
      readout.innerHTML = idle
    })
  }
}
