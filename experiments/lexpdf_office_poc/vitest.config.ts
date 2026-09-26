import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

const root = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  resolve: {
    alias: [
      {
        find: /^@genoffice\/docx-engine\/(.+)$/,
        replacement: path.resolve(root, 'vendor/genoffice/packages/docx-engine/src/$1.ts'),
      },
      {
        find: /^@genoffice\/pptx-engine\/(.+)$/,
        replacement: path.resolve(root, 'vendor/genoffice/packages/pptx-engine/src/$1.ts'),
      },
      {
        find: '@genoffice/docx-engine',
        replacement: path.resolve(root, 'vendor/genoffice/packages/docx-engine/src/index.ts'),
      },
      {
        find: '@genoffice/pptx-engine',
        replacement: path.resolve(root, 'vendor/genoffice/packages/pptx-engine/src/index.ts'),
      }
    ]
  },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.test.ts'],
    exclude: ['vendor/**', 'node_modules/**']
  }
})
