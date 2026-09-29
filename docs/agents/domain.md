# Domain Docs

LexPDF uses a **single-context** domain documentation layout.

## Before changing or reviewing code

Read, when present and relevant:

- `GLOSSARY.md` at the repository root;
- ADRs under `docs/adr/`;
- specifications and issues touching the area being changed;
- `AGENTS.md` for repository-level invariants.

If `GLOSSARY.md` or `docs/adr/` do not yet exist, proceed without creating empty placeholders. They should be created lazily only when real terminology or durable architectural decisions need to be recorded.

## Vocabulary and architectural decisions

Use established LexPDF terminology consistently. If a proposed change conflicts with an existing ADR or a documented invariant, surface the conflict explicitly instead of silently overriding it.

Critical reader invariants documented in `AGENTS.md` take precedence over generic refactoring preferences.
