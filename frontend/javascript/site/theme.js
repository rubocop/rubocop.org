// auto -> light -> dark. The head applies a saved choice before the first
// paint; this picks it up from there and handles clicks.
const MODES = ["auto", "light", "dark"]
const TITLES = {
  auto: "Color theme: follows your system",
  light: "Color theme: light",
  dark: "Color theme: dark",
}

export function setupTheme() {
  const button = document.getElementById("theme")
  if (!button) return

  let mode = document.documentElement.dataset.theme || "auto"

  const apply = () => {
    if (mode === "auto") document.documentElement.removeAttribute("data-theme")
    else document.documentElement.dataset.theme = mode
    button.dataset.mode = mode
    button.querySelector(".label").textContent = mode
    button.title = TITLES[mode]
  }

  apply()
  button.addEventListener("click", () => {
    mode = MODES[(MODES.indexOf(mode) + 1) % MODES.length]
    try { localStorage.setItem("theme", mode) } catch { /* storage blocked */ }
    apply()
  })
}
