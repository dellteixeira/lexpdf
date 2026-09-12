# LexPDF Render Core 2

Render Core 2 is executed as a sequence of hard gates. A later phase must not begin until the previous phase has objective evidence and is explicitly approved.

## Execution order

1. Visual baseline on the physical Windows 10 machine
2. Coordinate and scale audit
3. Isolated renderer branch/prototype boundary
4. Minimal native PDFium renderer
5. Exact physical-pixel full-page rendering
6. Native Texture/surface presentation path
7. Physical Windows 10 sharpness validation
8. Stop/fix loop until sharpness passes
9. Rendering benchmark document
10. Golden-image regression tests
11. Progressive zoom rendering
12. Memory-bounded LRU cache
13. Render scheduler and cancellation
14. High-zoom regional rendering/tiles only when necessary
15. Windows DPI/display-scale validation
16. Performance instrumentation
17. Workspace reintegration
18. Text selection and search reintegration
19. Thumbnail and navigation reintegration
20. Annotation autosave hardening
21. Windows 11 validation
22. Android architecture port
23. Reader UX cleanup
24. Study mode
25. Library and advanced features
26. Release Candidate only after visual, performance, CI, Windows 10 and Windows 11 gates pass

## Current gate

**Phase 1 — Visual baseline: IN PROGRESS / BLOCKING**

Run from `apps/lexpdf_app`:

```bash
python tool/validate_render_core2_visual_baseline.py
```

The validator is expected to fail until all required physical-test evidence has been entered into `tool/render_core2_visual_baseline.json` and the baseline is explicitly approved.

No Phase 2 implementation should be merged while the Phase 1 validator reports `BLOCKED`.
