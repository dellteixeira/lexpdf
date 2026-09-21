# WordPad document formats

The LexPDF notebook editor is a rich document editor rather than a plain text box.

## Native formats

- **DOCX** — import/export through the vendored Fluent Editor OOXML implementation, including rich paragraphs, lists, tables and images supported by that engine.
- **RTF** — in-app import/export with Unicode, paragraph boundaries and common inline formatting such as bold, italic, underline, strikeout and font size.
- **TXT** — UTF-8 text import/export.
- **PDF** — rich-document export through the existing PDF exporter.

## Legacy DOC

Binary Word 97–2003 `.doc` is not reimplemented or faked. On Windows, LexPDF enables DOC only when a real converter is detected:

1. LibreOffice/soffice, if installed; or
2. Microsoft Word COM automation, if Word is installed.

The conversion happens through temporary files and the temporary conversion directory is deleted afterwards.

On Android there is no native binary DOC converter in the app, so DOC is omitted from the open picker and disabled in Save As. DOCX, RTF, TXT and PDF remain available.

## Safety

- Office imports are size-bounded by the notebook screen before parsing.
- The app never writes DOCX bytes with a false `.doc` or `.rtf` extension.
- Unsupported legacy conversion fails explicitly rather than silently degrading the file.
