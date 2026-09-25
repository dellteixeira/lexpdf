import './styles.css'
import { OfficeSession } from './office-session'

const editorElement = document.querySelector<HTMLElement>('#editor')!

let currentName = 'Sem título.docx'
let dirty = false
let initializing = true

function notifyNative(payload: Record<string, unknown>) {
  const win = window as any
  try { win.flutter_inappwebview?.callHandler('LexPdfOfficeEvent', payload) } catch {}
  try { win.chrome?.webview?.postMessage(payload) } catch {}
  try { win.LexPdfAndroid?.postMessage(JSON.stringify(payload)) } catch {}
}

const session = new OfficeSession(editorElement, () => {
  if (initializing) return
  dirty = true
  notifyNative({ type: 'documentChanged', name: currentName })
})

async function openBytes(bytes: Uint8Array, name = 'documento.docx') {
  initializing = true
  try {
    await session.open(bytes)
    currentName = name
    dirty = false
    notifyNative({ type: 'documentOpened', name })
    queueMicrotask(() => session.editor.commands.focus('start'))
  } finally {
    initializing = false
  }
}

function newDocument(name = 'Sem título.docx') {
  initializing = true
  session.newDocument()
  currentName = name
  dirty = false
  initializing = false
  notifyNative({ type: 'documentOpened', name })
  return { ok: true, name }
}

async function saveBytes(): Promise<Uint8Array> {
  const bytes = await session.save()
  dirty = false
  notifyNative({
    type: 'documentSaved',
    name: currentName,
    size: bytes.byteLength,
  })
  return bytes
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

let warmPromise: Promise<unknown> | null = null
function warmEngine() {
  warmPromise ??= import('@genoffice/docx-engine')
  return warmPromise
}

;(window as any).LexPdfOffice = {
  newDocument: (name?: string) => newDocument(name ?? 'Sem título.docx'),
  openBase64: async (base64: string, name?: string) => {
    await openBytes(base64ToBytes(base64), name ?? 'documento.docx')
    return { ok: true, name: currentName }
  },
  saveBase64: async () => {
    const bytes = await saveBytes()
    return { ok: true, base64: bytesToBase64(bytes), name: currentName }
  },
  warmEngine,
  isDirty: () => dirty,
  undo: () => session.editor.chain().focus().undo().run(),
  redo: () => session.editor.chain().focus().redo().run(),
  toggleBold: () => session.editor.chain().focus().toggleBold().run(),
  toggleItalic: () => session.editor.chain().focus().toggleItalic().run(),
  toggleUnderline: () => session.editor.chain().focus().toggleUnderline().run(),
  toggleStrike: () => session.editor.chain().focus().toggleStrike().run(),
  focus: () => session.editor.commands.focus('start'),
  getStartupMetrics: () => ({
    ready: true,
    bootMs: Math.round(performance.now()),
    docxEngineLoaded: warmPromise !== null,
  }),
}

function initialize() {
  try {
    // OfficeSession já nasce com um documento vazio. Não repetimos setContent
    // nem carregamos o docx-engine durante o startup.
    initializing = false
    notifyNative({
      type: 'ready',
      bridge: 'LexPdfOffice',
      version: 4,
      name: currentName,
      startup: 'persistent-webview-minimal',
      bootMs: Math.round(performance.now()),
    })
  } catch (error) {
    console.error(error)
    notifyNative({
      type: 'runtimeError',
      message: error instanceof Error ? error.message : String(error),
    })
  }
}

initialize()
