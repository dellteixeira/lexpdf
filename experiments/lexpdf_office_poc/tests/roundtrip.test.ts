import { describe, expect, it } from 'vitest'
import JSZip from 'jszip'
import { buildBlankDocx, parseDocx, saveDocx, type SaveBlock } from '@genoffice/docx-engine'

describe('LexPDF Office POC / GenOffice round-trip', () => {
  it('abre um DOCX mínimo', async () => {
    const bytes = await buildBlankDocx()
    const parsed = await parseDocx(bytes)
    expect(parsed.blocks.some((block) => !block.hidden)).toBe(true)
  })

  it('devolve os bytes originais quando nada foi alterado', async () => {
    const bytes = await buildBlankDocx()
    const parsed = await parseDocx(bytes)
    const finalBlocks: SaveBlock[] = parsed.blocks
      .filter((block) => !block.hidden && block.docxIndex !== null)
      .map((block) => ({ kind: 'original', docxIndex: block.docxIndex as number }))

    const saved = await saveDocx(parsed, finalBlocks)
    expect(saved).toEqual(bytes)
  })

  it('edita texto e negrito, salva e reabre sem perder a estrutura DOCX', async () => {
    const bytes = await buildBlankDocx()
    const parsed = await parseDocx(bytes)

    const saved = await saveDocx(parsed, [
      {
        kind: 'generated',
        block: {
          type: 'paragraph',
          runs: [{ text: 'LexPDF Office POC', bold: true }],
        },
      },
    ])

    const reopened = await parseDocx(saved)
    const runs = reopened.blocks.flatMap((block) => block.runs ?? [])
    expect(runs.map((run) => run.text).join('')).toContain('LexPDF Office POC')
    expect(runs.some((run) => run.bold)).toBe(true)

    const zip = await JSZip.loadAsync(saved)
    expect(zip.file('word/document.xml')).not.toBeNull()
    expect(zip.file('word/styles.xml')).not.toBeNull()
  })
})
