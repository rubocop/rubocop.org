import fs from "node:fs"
import path from "node:path"
import { defineConfig } from "vite"
import tailwindcss from "@tailwindcss/vite"

const basePath = (process.env.BASE_PATH || "").replace(/\/$/, "")
const devServerUrl = "http://localhost:5173"

// Lets Bridgetown know the Vite dev server is running (see plugins/builders/vite.rb)
const devServerFile = path.resolve(".bridgetown-cache/frontend-bundling/vite-dev-server")

const bridgetownDevServer = {
  name: "bridgetown-dev-server",
  configureServer(server) {
    server.httpServer?.once("listening", () => {
      fs.mkdirSync(path.dirname(devServerFile), { recursive: true })
      fs.writeFileSync(devServerFile, devServerUrl)
    })

    const removeDevServerFile = () => fs.rmSync(devServerFile, { force: true })
    server.httpServer?.once("close", removeDevServerFile)
    process.once("exit", removeDevServerFile)
    process.once("SIGINT", () => process.exit())
    process.once("SIGTERM", () => process.exit())
  }
}

export default defineConfig({
  root: "frontend",
  base: `${basePath}/_bridgetown/static/`,
  plugins: [tailwindcss(), bridgetownDevServer],
  resolve: {
    alias: {
      $styles: path.resolve("frontend/styles"),
      $javascript: path.resolve("frontend/javascript"),
      $components: path.resolve("src/_components")
    }
  },
  server: {
    port: 5173,
    strictPort: true,
    origin: devServerUrl
  },
  build: {
    outDir: path.resolve("output/_bridgetown/static"),
    emptyOutDir: true,
    manifest: true,
    rollupOptions: {
      input: path.resolve("frontend/javascript/index.js")
    }
  }
})
