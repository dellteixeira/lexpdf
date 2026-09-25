# LexPDF Office POC

Prova de conceito isolada para validar edição local de DOCX no LexPDF usando o motor open-source do GenOffice, sem Electron e sem ONLYOFFICE DocumentServer.

## O que esta POC faz

- abre um DOCX local;
- parseia com `@genoffice/docx-engine`;
- edita parágrafos no Tiptap;
- altera negrito, itálico, sublinhado e tachado;
- salva novamente como DOCX;
- preserva blocos ainda não editáveis (tabelas, imagens e passthrough) como conteúdo original;
- expõe uma ponte JavaScript única para Windows WebView2 e Android WebView.

## GenOffice fixado

A POC baixa exatamente o commit:

`480548fd55f1be3593ee0d8e316a734751d58309`

O checkout fica em `vendor/genoffice` e não é versionado no LexPDF.

## Executar

```bash
cd experiments/lexpdf_office_poc
npm install
npm run dev
```

## Testar

```bash
npm test
npm run build
```

## Bridge nativa

```js
window.LexPdfOffice.openBase64(base64, "arquivo.docx")
window.LexPdfOffice.saveBase64()
window.LexPdfOffice.isDirty()
window.LexPdfOffice.undo()
window.LexPdfOffice.redo()
window.LexPdfOffice.toggleBold()
window.LexPdfOffice.toggleItalic()
window.LexPdfOffice.toggleUnderline()
```

Eventos são enviados para:

- Windows WebView2: `window.chrome.webview.postMessage(...)`
- Android WebView: `window.LexPdfAndroid.postMessage(JSON.stringify(...))`

## Limites deliberados

Nesta primeira POC, tabelas e imagens são exibidas/preservadas, mas ainda não editadas. O objetivo é provar o round-trip DOCX e a ponte cross-platform antes de portar paginação, tabelas e imagens editáveis do GenOffice.
