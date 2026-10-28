// Filters for the cop index. Every cop is already in the page; this only hides
// rows, and keeps the filters in the query string so a filtered view can be
// linked to.
// Facets each row carries in a data attribute.
const ROW_FIELDS = ["status", "fix", "index"]
const FIELDS = ["q", "plugin", "department", "since", ...ROW_FIELDS]

// "Style/*Literal*" works like a --show-cops pattern, anything else matches
// names and descriptions.
function matcher(query) {
  const text = query.trim().toLowerCase()
  if (!text) return () => true
  if (text.includes("*")) {
    const pattern = new RegExp(`^${text.split("*").map((part) => part.replace(/[.+?^${}()|[\]\\/]/g, "\\$&")).join(".*")}$`)
    return (row) => pattern.test(row.name)
  }
  return (row) => row.name.includes(text) || row.text.includes(text)
}

// "1.80" -> [1, 80], or null for anything that isn't a version. A comma
// counts as a dot, as some phone keyboards only offer one.
function version(text) {
  const typed = text.trim().replaceAll(",", ".")
  return /^\d+(\.\d+)*$/.test(typed) ? typed.split(".").map(Number) : null
}

function newer(added, since) {
  for (let i = 0; i < Math.max(added.length, since.length); i++) {
    const difference = (added[i] ?? 0) - (since[i] ?? 0)
    if (difference) return difference > 0
  }
  return false
}

export function setupCopIndex() {
  const form = document.querySelector(".filters")
  if (!form) return

  const count = form.querySelector(".count")
  const empty = document.querySelector(".no-match")
  const groups = [...document.querySelectorAll(".dept-group")].map((element) => ({
    element,
    plugin: element.dataset.plugin,
    department: element.dataset.department,
    rows: [...element.querySelectorAll("li")].map((element) => ({
      element,
      name: element.querySelector(".name").textContent.toLowerCase(),
      text: element.querySelector(".desc").textContent.toLowerCase(),
      added: version(element.querySelector(".since").textContent) ?? [],
      ...Object.fromEntries(ROW_FIELDS.map((field) => [field, element.dataset[field]])),
    })),
  }))
  const total = groups.reduce((sum, group) => sum + group.rows.length, 0)

  const params = new URLSearchParams(location.search)
  for (const field of FIELDS) {
    if (params.has(field)) form.elements[field].value = params.get(field)
  }

  let urlTimer
  const apply = () => {
    const values = Object.fromEntries(FIELDS.map((field) => [field, form.elements[field].value]))
    const matches = matcher(values.q)
    const facets = ROW_FIELDS.filter((field) => values[field])
    // Each gem has versions of its own, so "added after" goes by the
    // versions of the plugin that's picked, or the department's, or RuboCop's.
    const since = version(values.since)
    const gem = values.plugin || groups.find((group) => group.department === values.department)?.plugin || "rubocop"
    let shown = 0

    for (const group of groups) {
      const inGroup = (!values.plugin || group.plugin === values.plugin) && (!values.department || group.department === values.department) &&
        (!since || group.plugin === gem)
      let visible = 0
      for (const row of group.rows) {
        const show = inGroup && facets.every((field) => row[field] === values[field]) && matches(row) && (!since || newer(row.added, since))
        if (row.element.hidden === show) row.element.hidden = !show
        if (show) visible++
      }
      group.element.hidden = visible === 0
      shown += visible
    }

    count.textContent = shown === total ? `${total.toLocaleString("en")} cops` : `${shown.toLocaleString("en")} of ${total.toLocaleString("en")}`
    empty.hidden = shown > 0

    // Safari throttles replaceState, so don't call it on every keystroke.
    clearTimeout(urlTimer)
    urlTimer = setTimeout(() => {
      const query = new URLSearchParams(Object.entries(values).filter(([, value]) => value))
      history.replaceState(null, "", `${location.pathname}${query.size ? `?${query}` : ""}${location.hash}`)
    }, 400)
  }

  form.addEventListener("input", apply)
  form.addEventListener("submit", (event) => event.preventDefault())
  form.addEventListener("reset", () => setTimeout(apply))
  form.hidden = false
  apply()
}
