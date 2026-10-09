import build from "./config/esbuild.defaults.js"

const basePath = process.env.BASE_PATH || ""

/**
 * @typedef { import("esbuild").BuildOptions } BuildOptions
 * @type {BuildOptions}
 */
const esbuildOptions = {
  publicPath: `${basePath}/_bridgetown/static`
}

build(esbuildOptions)
