import build from "./config/esbuild.defaults.js"

// rubocop.org itself builds with BASE_PATH=/, which would otherwise turn the
// asset URLs into protocol-relative ones (//_bridgetown/...).
const basePath = (process.env.BASE_PATH || "").replace(/\/+$/, "")

/**
 * @typedef { import("esbuild").BuildOptions } BuildOptions
 * @type {BuildOptions}
 */
const esbuildOptions = {
  publicPath: `${basePath}/_bridgetown/static`,
  // The playground and its worker are separate bundles, so the rest of the
  // site doesn't load CodeMirror or the WebAssembly glue.
  entryPoints: [
    "./frontend/javascript/index.js",
    "./frontend/javascript/playground/index.js",
    "./frontend/javascript/playground/worker.js",
  ],
  loader: {
    ".woff2": "file",
    // the Ruby side of the playground, evaluated inside ruby.wasm
    ".rb": "text",
  }
}

build(esbuildOptions)
