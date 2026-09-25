import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

const root = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  resolve: {
    alias: [
      { find: '@genoffice/docx-engine', replacement: path.resolve(root, 'vendor/genoffice/packages/docx-engine/src') },
      { find: '@genoffice/pptx-engine', replacement: path.resolve(root, 'vendor/genoffice/packages/pptx-engine/src') }
    ]
  },
  test: { environment: 'jsdom' }
})
