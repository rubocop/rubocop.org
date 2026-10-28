// Playground state travels in the URL hash, deflated and base64url-encoded,
// so a link carries the code without any server keeping it.
const PREFIX = "v1="

function toBase64Url(bytes) {
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function fromBase64Url(text) {
  return Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0))
}

// The part of a link after the #. bin/check-pages.js builds links with it too.
export async function shareHash(data) {
  const stream = new Blob([JSON.stringify(data)]).stream().pipeThrough(new CompressionStream("deflate-raw"))
  return `${PREFIX}${toBase64Url(new Uint8Array(await new Response(stream).arrayBuffer()))}`
}

export async function shareLink(data) {
  return `${location.origin}${location.pathname}#${await shareHash(data)}`
}

// Links come from anywhere, so only strings get through.
function clean(data) {
  if (!data || typeof data !== "object") return null
  const text = (value) => (typeof value === "string" ? value : undefined)
  return { code: text(data.code), config: text(data.config), file: text(data.file), mode: text(data.mode) }
}

// A shared link wins over the last draft from this browser.
export async function readShared() {
  const hash = location.hash.slice(1)
  if (hash.startsWith(PREFIX)) {
    try {
      const stream = new Blob([fromBase64Url(hash.slice(PREFIX.length))]).stream().pipeThrough(new DecompressionStream("deflate-raw"))
      return clean(JSON.parse(await new Response(stream).text()))
    } catch { /* a mangled link falls back to the draft */ }
  }
  try {
    return clean(JSON.parse(localStorage.getItem("playground") || "null"))
  } catch {
    return null
  }
}
