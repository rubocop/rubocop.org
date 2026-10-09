// The header carries a line like RuboCop's progress formatter, one mark per
// section of the page: a dot for the ones you've read, a red C where you are.
export function setupProgress() {
  const line = document.querySelector(".run")
  const sections = [...document.querySelectorAll("[data-sec]")]
  if (!line || sections.length === 0) return

  let current = 0
  let furthest = 0

  const draw = () => {
    line.innerHTML = sections.map((_, i) => {
      if (i === current) return '<b class="here">C</b>'
      return i < furthest ? '<b class="ok">.</b>' : "<b>&middot;</b>"
    }).join("")
  }

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue
      current = sections.indexOf(entry.target)
      furthest = Math.max(furthest, current)
      draw()
    }
  }, { rootMargin: "-45% 0px -50% 0px" })

  sections.forEach((section) => observer.observe(section))
  draw()

  const summary = document.querySelector(".summary")
  if (summary) summary.textContent = `${sections.length} sections inspected, no offenses detected`
}
