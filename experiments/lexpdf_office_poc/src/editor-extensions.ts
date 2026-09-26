import { Mark, Node, mergeAttributes } from '@tiptap/core'

export const SourceRun = Mark.create({
  name: 'sourceRun',
  inclusive: true,
  addAttributes() {
    return { data: { default: null, rendered: false } }
  },
  parseHTML() {
    return [{ tag: 'span[data-source-run]' }]
  },
  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(HTMLAttributes, { 'data-source-run': '1' }), 0]
  },
})

export const LexBlock = Node.create({
  name: 'lexBlock',
  group: 'block',
  content: 'inline*',
  defining: true,
  addAttributes() {
    const hidden = (defaultValue: unknown) => ({
      default: defaultValue,
      rendered: false,
      keepOnSplit: false,
    })
    return {
      docxIndex: hidden(null),
      blockType: hidden('paragraph'),
      level: hidden(null),
      styleId: hidden(null),
      list: hidden(null),
      format: hidden(null),
      rawPPr: hidden(null),
      bookmarks: hidden(null),
      hiddenBookmarks: hidden(null),
      commentStarts: hidden(null),
      commentEnds: hidden(null),
      pPrChange: hidden(null),
      blockRevision: hidden(null),
    }
  },
  parseHTML() {
    return [{ tag: 'p[data-lex-block]' }]
  },
  renderHTML({ HTMLAttributes }) {
    return ['p', mergeAttributes(HTMLAttributes, { 'data-lex-block': '1' }), 0]
  },
})

export const PreservedBlock = Node.create({
  name: 'preservedBlock',
  group: 'block',
  atom: true,
  selectable: true,
  addAttributes() {
    return {
      docxIndex: { default: null, rendered: false },
      kind: { default: 'passthrough', rendered: false },
      label: { default: 'Conteúdo preservado', rendered: false },
      preview: { default: '', rendered: false },
      src: { default: null, rendered: false },
    }
  },
  parseHTML() {
    return [{ tag: '[data-preserved-block]' }]
  },
  renderHTML({ node }) {
    const { kind, label, preview, src } = node.attrs
    if (kind === 'image' && src) {
      return [
        'figure',
        { 'data-preserved-block': 'image', class: 'preserved preserved-image' },
        ['img', { src, alt: label || 'Imagem do DOCX' }],
        ['figcaption', {}, label || 'Imagem preservada'],
      ]
    }
    return [
      'div',
      { 'data-preserved-block': String(kind), class: 'preserved' },
      ['strong', {}, label || 'Conteúdo preservado'],
      ['small', {}, preview || 'Será mantido sem alteração no salvamento.'],
    ]
  },
})
