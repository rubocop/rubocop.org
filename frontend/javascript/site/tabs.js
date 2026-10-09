// Marks one tab of its tablist as selected.
export function selectTab(selected) {
  for (const tab of selected.closest("[role=tablist]").querySelectorAll("[role=tab]")) {
    tab.setAttribute("aria-selected", tab === selected)
  }
}

// Terminal tabs: each button names the <pre> it shows in data-out.
export function setupTabs() {
  for (const tabs of document.querySelectorAll(".term-tabs")) {
    tabs.addEventListener("click", (event) => {
      const selected = event.target.closest("[role=tab]")
      if (!selected) return
      selectTab(selected)
      for (const tab of tabs.querySelectorAll("[role=tab]")) document.getElementById(tab.dataset.out).hidden = tab !== selected
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
