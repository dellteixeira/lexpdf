import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const pocRoot = path.resolve(here, '..')
const source = path.join(pocRoot, 'dist')
const target = path.resolve(pocRoot, '../../apps/lexpdf_app/assets/office_runtime')

if (!existsSync(source)) {
  throw new Error('Vite dist not found. Run npm run build first.')
}

rmSync(target, { recursive: true, force: true })
mkdirSync(target, { recursive: true })
cpSync(source, target, { recursive: true })
console.log('[LexPDF Office POC] Flutter assets atualizados em', target)
