// Marks one tab of its tablist as selected. Only the selected tab is in the
// tab order; the arrow keys move between the others.
export function selectTab(selected) {
  for (const tab of selected.closest("[role=tablist]").querySelectorAll("[role=tab]")) {
    tab.setAttribute("aria-selected", tab === selected)
    tab.tabIndex = tab === selected ? 0 : -1
  }
}

const TAB_KEYS = ["ArrowLeft", "ArrowRight", "Home", "End"]

// Keyboard support for every tablist on the page, the usual way: arrows,
// Home and End move to a tab and select it. Selecting goes through click(),
// so each strip keeps its own handler.
export function setupTabKeys() {
  for (const selected of document.querySelectorAll("[role=tab][aria-selected=true]")) selectTab(selected)

  document.addEventListener("keydown", (event) => {
    if (!TAB_KEYS.includes(event.key) || event.altKey || event.ctrlKey || event.metaKey) return
    const current = event.target.closest?.("[role=tab]")
    if (!current) return
    const tabs = [...current.closest("[role=tablist]").querySelectorAll("[role=tab]")]
    const i = tabs.indexOf(current)
    const next = { ArrowLeft: tabs.at(i - 1), ArrowRight: tabs[(i + 1) % tabs.length], Home: tabs[0], End: tabs.at(-1) }[event.key]
    event.preventDefault()
    next.focus()
    next.click()
  })
}

// Terminal tabs: each button names the <pre> it shows in aria-controls.
export function setupTabs() {
  for (const tabs of document.querySelectorAll(".term-tabs")) {
    tabs.addEventListener("click", (event) => {
      const selected = event.target.closest("[role=tab]")
      if (!selected) return
      selectTab(selected)
      for (const tab of tabs.querySelectorAll("[role=tab]")) document.getElementById(tab.getAttribute("aria-controls")).hidden = tab !== selected
    })
  }
}

export function setupInstall() {
  const install = document.querySelector(".install")
  if (!install) return

  const command = install.querySelector("code")
  const prompt = install.querySelector(".p")
  const note = document.getElementById("install-note")

  install.querySelector(".install-tabs").addEventListener("click", (event) => {
    const selected = event.target.closest("[role=tab]")
    if (!selected) return
    selectTab(selected)
    command.textContent = selected.dataset.cmd
    prompt.textContent = selected.dataset.prompt
    note.textContent = selected.dataset.note
    note.hidden = !selected.dataset.note
  })

  const copy = install.querySelector(".copy")
  copy.addEventListener("click", () => {
    navigator.clipboard?.writeText(command.textContent).then(() => {
      copy.textContent = "copied"
      setTimeout(() => (copy.textContent = "copy"), 1400)
    })
  })
}
