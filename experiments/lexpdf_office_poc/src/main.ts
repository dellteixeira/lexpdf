import './styles.css'
import { OfficeSession } from './office-session'

const editorElement = document.querySelector<HTMLElement>('#editor')!
const fileInput = document.querySelector<HTMLInputElement>('#fileInput')!
const saveButton = document.querySelector<HTMLButtonElement>('#saveButton')!
const status = document.querySelector<HTMLElement>('#status')!

let currentName = 'documento.docx'
let dirty = false

function setStatus(text: string) {
  status.textContent = text
}

function notifyNative(payload: Record<string, unknown>) {
  const win = window as any
  try { win.flutter_inappwebview?.callHandler('LexPdfOfficeEvent', payload) } catch {}
  try { win.chrome?.webview?.postMessage(payload) } catch {}
  try { win.LexPdfAndroid?.postMessage(JSON.stringify(payload)) } catch {}
}

const session = new OfficeSession(editorElement, () => {
  if (!session.hasDocument) return
  dirty = true
  setStatus(currentName + ' • alterado')
  notifyNative({ type: 'documentChanged' })
})

async function openBytes(bytes: Uint8Array, name = 'documento.docx') {
  setStatus('Abrindo DOCX…')
  await session.open(bytes)
  currentName = name
  dirty = false
  saveButton.disabled = false
  setStatus(currentName + ' • pronto')
  notifyNative({ type: 'documentOpened', name })
}

async function saveBytes(): Promise<Uint8Array> {
  setStatus('Salvando DOCX…')
  const bytes = await session.save()
  dirty = false
  setStatus(currentName + ' • salvo')
  notifyNative({ type: 'documentSaved', name: currentName, size: bytes.byteLength })
  return bytes
}

fileInput.addEventListener('change', async () => {
  const file = fileInput.files?.[0]
  if (!file) return
  try {
    await openBytes(new Uint8Array(await file.arrayBuffer()), file.name)
  } catch (error) {
    console.error(error)
    setStatus('Falha ao abrir: ' + (error instanceof Error ? error.message : String(error)))
  } finally {
    fileInput.value = ''
  }
})

saveButton.addEventListener('click', async () => {
  try {
    const bytes = await saveBytes()
    const blob = new Blob([bytes], {
      type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = currentName.replace(/\.docx$/i, '') + '-lexpdf.docx'
    anchor.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  } catch (error) {
    console.error(error)
    setStatus('Falha ao salvar: ' + (error instanceof Error ? error.message : String(error)))
  }
})

document.querySelector('.toolbar')?.addEventListener('click', (event) => {
  const target = (event.target as HTMLElement).closest<HTMLButtonElement>('button[data-command]')
  if (!target) return
  const command = target.dataset.command
  const chain = session.editor.chain().focus()
  if (command === 'bold') chain.toggleBold().run()
  if (command === 'italic') chain.toggleItalic().run()
  if (command === 'underline') chain.toggleUnderline().run()
  if (command === 'strike') chain.toggleStrike().run()
  if (command === 'undo') chain.undo().run()
  if (command === 'redo') chain.redo().run()
})

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

;(window as any).LexPdfOffice = {
  openBase64: async (base64: string, name?: string) => {
    await openBytes(base64ToBytes(base64), name ?? 'documento.docx')
    return { ok: true }
  },
  saveBase64: async () => {
    const bytes = await saveBytes()
    return { ok: true, base64: bytesToBase64(bytes), name: currentName }
  },
  isDirty: () => dirty,
  undo: () => session.editor.chain().focus().undo().run(),
  redo: () => session.editor.chain().focus().redo().run(),
  toggleBold: () => session.editor.chain().focus().toggleBold().run(),
  toggleItalic: () => session.editor.chain().focus().toggleItalic().run(),
  toggleUnderline: () => session.editor.chain().focus().toggleUnderline().run(),
}

notifyNative({ type: 'ready', bridge: 'LexPdfOffice', version: 1 })
