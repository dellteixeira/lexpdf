# ADR 0001 — PDF engine

## Status
Accepted for the first reader milestone.

## Decision
Use `pdfrx` as the first PDF rendering/viewing layer. It is built on PDFium, supports Android, Windows and macOS, and keeps the PDF engine replaceable behind LexPDF application interfaces.

## Constraints
- Offline rendering is mandatory.
- No cloud dependency may be introduced by the viewer.
- Annotation data remains owned by LexPDF and must not be coupled to the viewer package.
- The package can be replaced later without changing the document provider or local catalog contracts.

## Non-goals in this milestone
Text editing, OCR, ink annotations and cloud synchronization are not implemented by this ADR.
