# LexPDF Office POC — decisão experimental

Branch: `poc/genoffice-docx`

## Objetivo

Validar se o LexPDF pode adotar um editor DOCX local-first baseado no GenOffice e Tiptap, mantendo ONLYOFFICE apenas como fallback opcional.

## Pipeline

```text
DOCX bytes
  -> @genoffice/docx-engine / parseDocx()
  -> Block[]
  -> Tiptap / ProseMirror
  -> edição local
  -> SaveBlock[]
  -> @genoffice/docx-engine / saveDocx()
  -> DOCX bytes
```

O Electron do GenOffice não participa desse fluxo.

## Gate A — engine e round-trip

- [x] Motor GenOffice isolado do Electron.
- [x] Commit upstream fixado.
- [x] Abrir DOCX por bytes.
- [x] Editar texto.
- [x] Editar formatação básica.
- [x] Salvar DOCX por bytes.
- [x] Reparsear automaticamente o resultado.
- [x] Preservar blocos não editados como `kind: original`.
- [ ] Abrir o DOCX salvo no Microsoft Word e confirmar ausência de reparo.
- [ ] Abrir o DOCX salvo no LibreOffice e confirmar ausência de reparo.

## Gate B — fidelidade visual

- [ ] Tabelas editáveis.
- [x] Tabelas não editadas preservadas.
- [ ] Imagens editáveis.
- [x] Imagens não editadas preservadas.
- [ ] Paginação equivalente ao Word.
- [ ] Cabeçalho/rodapé editáveis.
- [ ] Track Changes.
- [ ] Comentários.

## Gate C — integração LexPDF

- [x] Bridge JavaScript comum.
- [x] Canal WebView2 previsto no runtime.
- [x] Canal Android WebView previsto no runtime.
- [ ] Tela Flutter Windows carregando o runtime.
- [ ] Tela Flutter Android carregando o runtime.
- [ ] Teste de teclado/IME Android.
- [ ] Teste com DOCX de 10 MB, 50 MB e 100 MB.
- [ ] Teste de memória em Android.

## Regra de decisão

Não remover ONLYOFFICE da arquitetura até Gates A, B e C demonstrarem compatibilidade suficiente com documentos reais.

Se Windows/Android e fidelidade passarem, a arquitetura preferida será:

```text
LexPDF Flutter
  -> WebView/WebView2
  -> LexPDF Office Runtime
  -> Tiptap
  -> GenOffice docx-engine
  -> arquivo local / Supabase
```

ONLYOFFICE permanece como fallback para documentos complexos que o motor local não consiga editar com fidelidade.
