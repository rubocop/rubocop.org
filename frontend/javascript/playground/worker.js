// Runs RuboCop on ruby.wasm, off the main thread. The page sends
// {type: "boot"} once, then {type: "run", id, file, mode, source, config}.
import { WASI, File, Directory, OpenFile, PreopenDirectory, ConsoleStdout } from "@bjorn3/browser_wasi_shim"
import { RubyVM } from "@ruby/wasm-wasi"
import renderer from "../../../plugins/rubocop_html.rb"
import prelude from "./prelude.rb"

const encoder = new TextEncoder()
const decoder = new TextDecoder()
let vm, inbox, booting

async function fetchOk(url) {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`)
  return response
}

// Reports bytes as they arrive, from a copy of the stream, so the response
// itself can go straight to the compiler (and the browser's code cache).
function count(response, onBytes) {
  response.clone().body.pipeTo(new WritableStream({ write: (chunk) => onBytes(chunk.byteLength) })).catch(() => {})
  return response
}

// The gem bundle is stored gzipped. Some hosts decode it on the way, so only
// gunzip when the bytes still start with the gzip magic number.
async function gunzipped(response) {
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (bytes[0] !== 0x1f || bytes[1] !== 0x8b) return bytes
  return new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer())
}

// A minimal ustar reader that builds the nested Maps browser_wasi_shim wants.
function untar(bytes) {
  const root = new Map()
  const field = (offset, length) => decoder.decode(bytes.subarray(offset, offset + length)).replace(/\0.*$/s, "")
  let offset = 0
  while (offset + 512 <= bytes.length && bytes[offset] !== 0) {
    const name = field(offset, 100)
    const prefix = field(offset + 345, 155)
    const size = parseInt(field(offset + 124, 12).trim() || "0", 8)
    const type = String.fromCharCode(bytes[offset + 156] || 48)
    const parts = (prefix ? `${prefix}/${name}` : name).split("/").filter(Boolean)
    let dir = root
    const depth = type === "5" ? parts.length : parts.length - 1
    for (let i = 0; i < depth; i++) {
      if (!dir.has(parts[i])) dir.set(parts[i], new Directory(new Map()))
      dir = dir.get(parts[i]).contents
    }
    if (type === "0") dir.set(parts.at(-1), new File(bytes.subarray(offset + 512, offset + 512 + size)))
    offset += 512 + Math.ceil(size / 512) * 512
  }
  return root
}

async function boot({ runtime, gems }) {
  const started = performance.now()
  const total = runtime.size + gems.size
  let loaded = 0
  let percent = -1
  const progress = (bytes) => {
    loaded += bytes
    const now = Math.min(100, Math.floor((loaded / total) * 100))
    if (now !== percent) postMessage({ type: "progress", percent: (percent = now) })
  }

  const [module, files] = await Promise.all([
    fetchOk(runtime.url).then((response) => WebAssembly.compileStreaming(count(response, progress))),
    fetchOk(gems.url).then((response) => gunzipped(count(response, progress))).then(untar),
  ])

  postMessage({ type: "status", text: "starting ruby" })
  inbox = new Directory(new Map())
  const fds = [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((line) => console.log(line)),
    ConsoleStdout.lineBuffered((line) => console.warn(line)),
    new PreopenDirectory("/", new Map([
      ["gems", new Directory(files)],
      ["work", new Directory(new Map())],
      ["pg", inbox],
    ])),
  ]
  const wasi = new WASI([], ["GEM_HOME=/gems", "GEM_PATH=/gems", "HOME=/work"], fds, { debug: false })
  ;({ vm } = await RubyVM.instantiateModule({ module, wasip1: wasi }))

  postMessage({ type: "status", text: "loading rubocop" })
  vm.eval(renderer)
  vm.eval('Dir.chdir("/work")')
  vm.eval(prelude)
  vm.eval("Playground.warm_up")
  postMessage({
    type: "ready",
    version: vm.eval("RuboCop::Version::STRING").toString(),
    ruby: vm.eval("RUBY_VERSION").toString(),
    ms: Math.round(performance.now() - started),
  })
}

// Everything from the page reaches Ruby as a file in /pg, never as code.
function put(name, text) {
  inbox.contents.set(name, new File(encoder.encode(text)))
}

function run({ id, file, mode, source, config }) {
  put("request.json", JSON.stringify({ file, mode }))
  put("source", source)
  put("config.yml", config)
  const started = performance.now()
  const output = JSON.parse(vm.eval("Playground.run").toString())
  postMessage({ type: "result", id, ms: Math.round(performance.now() - started), ...output })
}

onmessage = async ({ data }) => {
  try {
    if (data.type === "boot") {
      booting ??= boot(data)
      await booting
    } else if (data.type === "run") {
      await booting
      run(data)
    }
  } catch (error) {
    postMessage({ type: "error", id: data.id, message: String(error?.message || error) })
  }
}
