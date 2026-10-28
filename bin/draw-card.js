#!/usr/bin/env node
// Draws the picture link previews show: the built src/card.erb, at 1200 by
// 630, into images/card.png in the built site.
//
//   bin/draw-card.js [dir]   (output/ by default)

import { writeFile } from "node:fs/promises"
import { join } from "node:path"
import { BASE, Browser, serve } from "./chrome.js"

const ROOT = process.argv[2] ?? "output"
const [WIDTH, HEIGHT] = [1200, 630]

const server = await serve(ROOT)
const browser = await Browser.launch()
try {
  const page = await browser.open(`http://127.0.0.1:${server.address().port}${BASE}card.html`, WIDTH, HEIGHT)
  await page.evaluate("document.fonts.ready.then(() => true)")
  const { data } = await page.send("Page.captureScreenshot", { format: "png" })
  await writeFile(join(ROOT, "images", "card.png"), Buffer.from(data, "base64"))
  if (page.errors.length) throw new Error(`the card logged errors:\n${page.errors.join("\n")}`)
} finally {
  await browser.close()
  server.close()
}
