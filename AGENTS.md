# LexPDF Agent Instructions

## Agent skills

### Issue tracker

Issues and specifications are tracked in GitHub Issues for `dellteixeira/lexpdf`. See `docs/agents/issue-tracker.md`.

### Domain docs

This repository uses a single-context domain documentation layout. Read `GLOSSARY.md` when present and relevant ADRs under `docs/adr/`. See `docs/agents/domain.md`.

## LexPDF invariants

Preserve the existing critical reader architecture unless a change is explicitly justified by evidence and validated by the relevant gates:

- Android native reader based on Mozilla PDF.js in process `:pdfreader`
- 512 KB range reads
- import streaming with 64 KB buffer
- stable large-PDF support and reader-first opening
- reading progress via `LocalReadingProgressStore`
- Android landscape toolbar in one 48 dp row
- notebook/stroke persistence
- pen and highlighter settings persistence

Relevant implementation changes should be validated against the existing CI gates, including Backend Foundation, Flutter Foundation, Phase 3 Exit Gate, and Release Hardening when applicable.
