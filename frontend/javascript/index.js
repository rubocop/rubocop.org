import "$styles/index.css"

// Import all JavaScript & CSS files from src/_components
import components from "$components/**/*.{js,jsx,js.rb,css}"

// Copy-to-clipboard
document.addEventListener("click", (e) => {
  const btn = e.target.closest(".copy-btn")
  if (!btn) return

  const text = btn.dataset.copy
  navigator.clipboard.writeText(text).then(() => {
    btn.classList.add("copied")
    setTimeout(() => btn.classList.remove("copied"), 700)
  })
})

// Before/After code tabs
document.querySelectorAll(".code-tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    const tabs = tab.closest(".code-tabs").querySelectorAll(".code-tab")
    tabs.forEach((t) => t.classList.remove("active"))
    tab.classList.add("active")

    const codeBefore = document.getElementById("code-before")
    const codeAfter = document.getElementById("code-after")
    if (tab.dataset.tab === "after") {
      codeBefore.classList.add("hidden")
      codeAfter.classList.remove("hidden")
    } else {
      codeAfter.classList.add("hidden")
      codeBefore.classList.remove("hidden")
    }
  })
})

// Mobile nav toggle
const navToggle = document.getElementById("nav-toggle")
const navMobile = document.getElementById("navbar-mobile")
const iconMenu = document.getElementById("nav-icon-menu")
const iconX = document.getElementById("nav-icon-x")

if (navToggle && navMobile) {
  navToggle.addEventListener("click", () => {
    const isOpen = navMobile.classList.contains("flex")
    navMobile.classList.toggle("hidden", isOpen)
    navMobile.classList.toggle("flex", !isOpen)
    iconMenu.classList.toggle("opacity-0", !isOpen)
    iconMenu.classList.toggle("opacity-100", isOpen)
    iconX.classList.toggle("opacity-0", isOpen)
    iconX.classList.toggle("opacity-100", !isOpen)
  })
}
