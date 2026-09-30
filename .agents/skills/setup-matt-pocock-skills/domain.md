# Domain Docs

How engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- `GLOSSARY.md` at the repo root, or `GLOSSARY-MAP.md` if present
- ADRs under `docs/adr/`

If they do not exist, proceed silently. Domain-modeling creates them lazily when real terms or decisions are resolved.

## Layout

This repo uses a single-context layout:

```
/
├── GLOSSARY.md
├── docs/adr/
└── src/
```

Use glossary vocabulary consistently and surface conflicts with existing ADRs instead of silently overriding them.
