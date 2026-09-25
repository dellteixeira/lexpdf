import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const root = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  base: './',
  resolve: {
    alias: [
      { find: '@genoffice/docx-engine', replacement: path.resolve(root, 'vendor/genoffice/packages/docx-engine/src/index.ts') },
      { find: '@genoffice/pptx-engine', replacement: path.resolve(root, 'vendor/genoffice/packages/pptx-engine/src/index.ts') }
    ]
  },
  build: {
    target: 'es2022',
    assetsDir: 'assets',
    sourcemap: false
  }
})
