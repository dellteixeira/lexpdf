import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Underline from '@tiptap/extension-underline'
import {
  parseDocx,
  saveDocx,
  type Block,
  type GeneratedBlock,
  type ParsedDocFull,
  type Run,
  type SaveBlock,
} from '@genoffice/docx-engine'
import { LexBlock, PreservedBlock, SourceRun } from './editor-extensions'

type JsonMark = { type: string; attrs?: Record<string, unknown> }
type JsonNode = {
  type: string
  attrs?: Record<string, any>
  text?: string
  marks?: JsonMark[]
  content?: JsonNode[]
}

function runMarks(run: Run): JsonMark[] {
  const marks: JsonMark[] = [{ type: 'sourceRun', attrs: { data: run } }]
  if (run.bold) marks.push({ type: 'bold' })
  if (run.italic) marks.push({ type: 'italic' })
  if (run.underline) marks.push({ type: 'underline' })
  if (run.strike) marks.push({ type: 'strike' })
  return marks
}

function blockToEditorNode(block: Block): JsonNode | null {
  if (block.hidden) return null

  if (block.type === 'paragraph' || block.type === 'heading' || block.type === 'listItem') {
    const content = (block.runs ?? [])
      .filter((run) => run.text.length > 0)
      .map((run) => ({ type: 'text', text: run.text, marks: runMarks(run) }))

    return {
      type: 'lexBlock',
      attrs: {
        docxIndex: block.docxIndex,
        blockType: block.type,
        level: block.level ?? null,
        styleId: block.styleId ?? null,
        list: block.list ?? null,
        format: block.format ?? null,
        rawPPr: block.rawPPr ?? null,
        bookmarks: block.bookmarks ?? null,
        hiddenBookmarks: block.hiddenBookmarks ?? null,
        commentStarts: block.commentStarts ?? null,
        commentEnds: block.commentEnds ?? null,
        pPrChange: (block as any).pPrChange ?? null,
        blockRevision: (block as any).blockRevision ?? null,
      },
      ...(content.length ? { content } : {}),
    }
  }

  return {
    type: 'preservedBlock',
    attrs: {
      docxIndex: block.docxIndex,
      kind: block.type,
      label: block.label || (block.type === 'table' ? 'Tabela preservada' : 'Objeto preservado'),
      preview: block.previewText || '',
      src: block.type === 'image' ? block.imageDataUrl ?? null : null,
    },
  }
}

function updateBoolean(
  run: Run,
  source: Run,
  field: 'bold' | 'italic' | 'underline' | 'strike',
  now: boolean,
) {
  const before = Boolean(source[field])
  if (before === now) {
    if (source[field] === undefined) delete run[field]
    else run[field] = source[field]
  } else {
    run[field] = now
  }
}

function editorInlineToRuns(content: JsonNode[] | undefined): Run[] {
  const runs: Run[] = []
  for (const node of content ?? []) {
    if (node.type !== 'text') continue
    const sourceMark = node.marks?.find((mark) => mark.type === 'sourceRun')
    const source = (sourceMark?.attrs?.data ?? {}) as Run
    const run: Run = { ...source, text: node.text ?? '' }
    const has = (name: string) => Boolean(node.marks?.some((mark) => mark.type === name))
    updateBoolean(run, source, 'bold', has('bold'))
    updateBoolean(run, source, 'italic', has('italic'))
    updateBoolean(run, source, 'underline', has('underline'))
    updateBoolean(run, source, 'strike', has('strike'))
    runs.push(run)
  }
  return runs
}

function generatedFromOriginal(block: Block): GeneratedBlock {
  return {
    type: block.type === 'heading' || block.type === 'listItem' ? block.type : 'paragraph',
    ...(block.level !== undefined ? { level: block.level } : {}),
    ...(block.outlineOnly !== undefined ? { outlineOnly: block.outlineOnly } : {}),
    ...(block.styleId !== undefined ? { styleId: block.styleId } : {}),
    ...(block.list !== undefined ? { list: block.list } : {}),
    ...(block.format !== undefined ? { format: block.format } : {}),
    ...(block.rawPPr !== undefined ? { rawPPr: block.rawPPr } : {}),
    ...(block.bookmarks !== undefined ? { bookmarks: block.bookmarks } : {}),
    ...(block.hiddenBookmarks !== undefined ? { hiddenBookmarks: block.hiddenBookmarks } : {}),
    ...(block.commentStarts !== undefined ? { commentStarts: block.commentStarts } : {}),
    ...(block.commentEnds !== undefined ? { commentEnds: block.commentEnds } : {}),
    runs: block.runs ?? [],
  }
}

function editorNodeToGenerated(node: JsonNode): GeneratedBlock {
  const attrs = node.attrs ?? {}
  const blockType = attrs.blockType
  return {
    type: blockType === 'heading' || blockType === 'listItem' ? blockType : 'paragraph',
    ...(attrs.level != null ? { level: attrs.level } : {}),
    ...(attrs.styleId != null ? { styleId: attrs.styleId } : {}),
    ...(attrs.list != null ? { list: attrs.list } : {}),
    ...(attrs.format != null ? { format: attrs.format } : {}),
    ...(attrs.rawPPr != null ? { rawPPr: attrs.rawPPr } : {}),
    ...(attrs.bookmarks != null ? { bookmarks: attrs.bookmarks } : {}),
    ...(attrs.hiddenBookmarks != null ? { hiddenBookmarks: attrs.hiddenBookmarks } : {}),
    ...(attrs.commentStarts != null ? { commentStarts: attrs.commentStarts } : {}),
    ...(attrs.commentEnds != null ? { commentEnds: attrs.commentEnds } : {}),
    runs: editorInlineToRuns(node.content),
  }
}

const stable = (value: unknown) => JSON.stringify(value)

export class OfficeSession {
  readonly editor: Editor
  private parsed: ParsedDocFull | null = null

  constructor(element: HTMLElement, onChanged?: () => void) {
    this.editor = new Editor({
      element,
      extensions: [
        StarterKit.configure({
          paragraph: false,
          heading: false,
          bulletList: false,
          orderedList: false,
          listItem: false,
        }),
        Underline,
        SourceRun,
        LexBlock,
        PreservedBlock,
      ],
      content: { type: 'doc', content: [{ type: 'lexBlock' }] },
      onUpdate: () => onChanged?.(),
    })
  }

  async open(bytes: Uint8Array): Promise<void> {
    this.parsed = await parseDocx(bytes)
    const content = this.parsed.blocks
      .map(blockToEditorNode)
      .filter((node): node is JsonNode => node !== null)

    this.editor.commands.setContent({
      type: 'doc',
      content: content.length ? content : [{ type: 'lexBlock' }],
    })
  }

  async save(): Promise<Uint8Array> {
    if (!this.parsed) throw new Error('Nenhum DOCX está aberto.')

    const json = this.editor.getJSON() as JsonNode
    const originals = new Map(
      this.parsed.blocks
        .filter((block) => block.docxIndex !== null)
        .map((block) => [block.docxIndex as number, block]),
    )

    const finalBlocks: SaveBlock[] = []

    for (const node of json.content ?? []) {
      const docxIndex = node.attrs?.docxIndex

      if (node.type === 'preservedBlock') {
        if (typeof docxIndex !== 'number') {
          throw new Error('A POC não permite criar novos blocos preservados.')
        }
        finalBlocks.push({ kind: 'original', docxIndex })
        continue
      }

      if (node.type !== 'lexBlock') continue

      const generated = editorNodeToGenerated(node)
      const original = typeof docxIndex === 'number' ? originals.get(docxIndex) : undefined

      if (original && stable(generated) === stable(generatedFromOriginal(original))) {
        finalBlocks.push({ kind: 'original', docxIndex })
      } else {
        finalBlocks.push({ kind: 'generated', block: generated })
      }
    }

    return saveDocx(this.parsed, finalBlocks)
  }

  get hasDocument(): boolean {
    return this.parsed !== null
  }

  destroy(): void {
    this.editor.destroy()
  }
}
