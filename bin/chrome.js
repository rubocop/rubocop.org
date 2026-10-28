// Headless Chrome for bin/check-pages.js and bin/draw-card.js: a server for
// the built site, and just enough of the DevTools protocol to drive pages.
//
// BASE_PATH serves the site where it was built for, and CHROME names the
// browser when it isn't installed in the usual place.

import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { extname, join, resolve, sep } from "node:path"

export const BASE = `/${(process.env.BASE_PATH ?? "").replace(/^\/|\/$/g, "")}/`.replace("//", "/")
const CHROME = process.env.CHROME ?? {
  darwin: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  linux: "google-chrome",
}[process.platform]

// How long a page gets to load, and Chrome to answer a command.
const LOAD = 30_000
const ANSWER = 60_000

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json",
  ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2", ".gz": "application/gzip",
}

export function serve(root) {
  const top = resolve(root)
  const server = createServer(async (request, response) => {
    try {
      let path = decodeURIComponent(new URL(request.url, "http://localhost").pathname)
      if (path.endsWith("/")) path += "index.html"
      const file = resolve(top, `.${path.slice(BASE.length - 1)}`)
      if (!path.startsWith(BASE) || !file.startsWith(top + sep)) throw new Error("outside the site")
      response.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" }).end(await readFile(file))
    } catch {
      response.writeHead(404, { "content-type": TYPES[".html"] }).end(await readFile(join(top, "404.html")))
    }
  })
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)))
}

const timeout = (ms, what) => new Promise((_, reject) => setTimeout(() => reject(new Error(`${what} took over ${ms / 1000}s`)), ms).unref())

// Chrome, and just enough of the DevTools protocol: commands, and events per
// page. A command Chrome doesn't answer, because it crashed or hung, fails
// rather than waits forever.
export class Browser {
  #chrome
  #exited
  #profile
  #socket
  #id = 0
  #calls = new Map()
  #pages = new Map()

  static async launch() {
    const browser = new Browser()
    await browser.#start()
    return browser
  }

  async #start() {
    this.#profile = await mkdtemp(join(tmpdir(), "check-pages-"))
    const args = [
      "--headless", "--remote-debugging-port=0", `--user-data-dir=${this.#profile}`, "--no-first-run",
      "--no-default-browser-check", "--hide-scrollbars",
      // Ubuntu's AppArmor rules keep Chrome's sandbox from starting on CI.
      ...(process.env.CI ? ["--no-sandbox"] : []),
    ]
    this.#chrome = spawn(CHROME, [...args, "about:blank"], { stdio: ["ignore", "ignore", "pipe"] })
    this.#exited = new Promise((resolve) => this.#chrome.once("exit", resolve))
    const url = await new Promise((resolve, reject) => {
      let log = ""
      this.#chrome.stderr.on("data", (chunk) => {
        log += chunk
        const listening = log.match(/DevTools listening on (ws:\S+)/)
        if (listening) resolve(listening[1])
      })
      this.#chrome.on("error", reject)
      this.#chrome.on("exit", (code) => reject(new Error(`Chrome exited with ${code}:\n${log}`)))
    })
    this.#socket = new WebSocket(url)
    await new Promise((resolve, reject) => {
      this.#socket.onopen = resolve
      this.#socket.onerror = () => reject(new Error(`couldn't connect to ${url}`))
    })
    this.#socket.onclose = () => this.#fail(undefined, "Chrome went away")
    this.#socket.onmessage = ({ data }) => {
      const message = JSON.parse(data)
      const call = this.#calls.get(message.id)
      if (call) {
        this.#calls.delete(message.id)
        clearTimeout(call.timer)
        if (message.error) call.reject(new Error(`${call.method}: ${message.error.message}`))
        else call.resolve(message.result)
      } else {
        if (message.method === "Inspector.targetCrashed") this.#fail(message.sessionId, "the page crashed")
        this.#pages.get(message.sessionId)?.handle(message)
      }
    }
  }

  send(method, params = {}, sessionId) {
    if (this.#socket.readyState !== WebSocket.OPEN) return Promise.reject(new Error(`${method}: Chrome went away`))
    const id = ++this.#id
    this.#socket.send(JSON.stringify({ id, method, params, sessionId }))
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#calls.delete(id)
        reject(new Error(`${method}: Chrome didn't answer in ${ANSWER / 1000}s`))
      }, ANSWER).unref()
      this.#calls.set(id, { resolve, reject, method, timer, sessionId })
    })
  }

  // Fails the commands waiting on a page, or on all of them.
  #fail(sessionId, why) {
    for (const [id, call] of this.#calls) {
      if (sessionId && call.sessionId !== sessionId) continue
      this.#calls.delete(id)
      clearTimeout(call.timer)
      call.reject(new Error(`${call.method}: ${why}`))
    }
  }

  async open(url, width = 1280, height = 900) {
    const { targetId } = await this.send("Target.createTarget", { url: "about:blank" })
    const { sessionId } = await this.send("Target.attachToTarget", { targetId, flatten: true })
    const page = new Page(this, sessionId, targetId, url)
    this.#pages.set(sessionId, page)
    await Promise.all(["Page.enable", "Runtime.enable", "Log.enable", "Inspector.enable"].map((method) => page.send(method)))
    await page.resize(width, height)
    await page.go(url)
    return page
  }

  async close() {
    if (this.#chrome.exitCode === null && this.#chrome.signalCode === null) {
      await this.send("Browser.close").catch(() => this.#chrome.kill("SIGKILL"))
      await Promise.race([this.#exited, timeout(LOAD, "closing Chrome")]).catch(() => this.#chrome.kill("SIGKILL"))
    }
    // Chrome's helpers can still be writing to the profile for a moment.
    await rm(this.#profile, { recursive: true, force: true, maxRetries: 10 })
  }
}

class Page {
  // What the page logged as an error: exceptions, console.error and failed
  // requests for the site's own files.
  errors = []
  #loaded

  constructor(browser, sessionId, targetId, url) {
    this.browser = browser
    this.sessionId = sessionId
    this.targetId = targetId
    this.origin = new URL(url).origin
  }

  send(method, params) {
    return this.browser.send(method, params, this.sessionId)
  }

  handle({ method, params }) {
    if (method === "Page.loadEventFired") {
      this.#loaded?.()
    } else if (method === "Inspector.targetCrashed") {
      this.errors.push("the page crashed")
    } else if (method === "Runtime.exceptionThrown") {
      this.errors.push(params.exceptionDetails.exception?.description ?? params.exceptionDetails.text)
    } else if (method === "Runtime.consoleAPICalled" && params.type === "error") {
      this.errors.push(params.args.map((arg) => arg.value ?? arg.description).join(" "))
    } else if (method === "Log.entryAdded" && params.entry.level === "error" && (params.entry.url ?? this.origin).startsWith(this.origin)) {
      this.errors.push(`${params.entry.text} ${params.entry.url ?? ""}`.trim())
    }
  }

  async go(url) {
    const loaded = new Promise((resolve) => (this.#loaded = resolve))
    await this.send("Page.navigate", { url })
    await Promise.race([loaded, timeout(LOAD, `loading ${url}`)])
  }

  resize(width, height = 900) {
    return this.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false })
  }

  async evaluate(expression) {
    const { result, exceptionDetails } = await this.send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true })
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text)
    return result.value
  }

  // Evaluates until the expression comes out truthy, and returns the last
  // value either way.
  async waitFor(expression, ms = 5000) {
    const deadline = Date.now() + ms
    for (;;) {
      const value = await this.evaluate(expression)
      if (value || Date.now() > deadline) return value
      await new Promise((resolve) => setTimeout(resolve, 100))
    }
  }

  async press(key) {
    for (const type of ["keyDown", "keyUp"]) await this.send("Input.dispatchKeyEvent", { type, key, code: key })
  }

  close() {
    return this.browser.send("Target.closeTarget", { targetId: this.targetId })
  }
}
