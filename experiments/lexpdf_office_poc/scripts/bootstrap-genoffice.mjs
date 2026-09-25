import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const GENOFFICE_REPO = 'https://github.com/genspark-ai/genoffice.git'
const GENOFFICE_COMMIT = '480548fd55f1be3593ee0d8e316a734751d58309'

const here = path.dirname(fileURLToPath(import.meta.url))
const pocRoot = path.resolve(here, '..')
const vendorRoot = path.join(pocRoot, 'vendor')
const checkout = path.join(vendorRoot, 'genoffice')
const stamp = path.join(checkout, '.lexpdf-pinned-commit')

if (existsSync(stamp) && readFileSync(stamp, 'utf8').trim() === GENOFFICE_COMMIT) {
  console.log('[LexPDF Office POC] GenOffice já está no commit fixado.')
  process.exit(0)
}

rmSync(checkout, { recursive: true, force: true })
mkdirSync(vendorRoot, { recursive: true })

execFileSync('git', ['init', checkout], { stdio: 'inherit' })
execFileSync('git', ['-C', checkout, 'remote', 'add', 'origin', GENOFFICE_REPO], { stdio: 'inherit' })
execFileSync('git', ['-C', checkout, 'fetch', '--depth', '1', 'origin', GENOFFICE_COMMIT], { stdio: 'inherit' })
execFileSync('git', ['-C', checkout, 'checkout', '--detach', 'FETCH_HEAD'], { stdio: 'inherit' })
writeFileSync(stamp, GENOFFICE_COMMIT + '\n')

console.log('[LexPDF Office POC] GenOffice pronto em', GENOFFICE_COMMIT)
