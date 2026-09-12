# LexPDF Render Core 2 — Phase 1 Visual Baseline

## Status

**Gate: BLOCKED / IN PROGRESS**

Render Core 2 must not advance to Phase 2 until this baseline is complete and reviewed on the physical Windows 10 machine that reproduces the defect.

Current confirmed observation:

- LexPDF at 75%: **FAIL** — PDF page content is severely blurred/deformed while the Flutter chrome and ink overlay remain sharp.
- 100%, 125%, 200%, 300%, 400%: pending evidence.
- Reference reader captures: pending evidence.

The current Windows 10 manual tile experiment is therefore **not accepted as the final rendering architecture**.

## Fixed test document

Use the same PDF that reproduces the defect in the physical test:

`tratado_leis_especiais_concursos_2026_atualizado_15-08-2026.pdf`

Do not change the document between LexPDF and the reference reader.

## Fixed environment record

Before collecting screenshots, record:

- Windows edition/version/build
- Display resolution
- Windows display scaling percentage
- Monitor model if known
- LexPDF commit SHA
- LexPDF build/version
- Reference reader and version
- Whether the window is maximized

All screenshots in a comparison set must use the same machine, monitor, resolution, Windows scaling, document page, and approximately the same viewport.

## Mandatory zoom matrix

Collect paired screenshots for each zoom level:

| Zoom | LexPDF | Reference reader | Gate |
|---:|---|---|---|
| 75% | FAIL observed | pending | pending |
| 100% | pending | pending | pending |
| 125% | pending | pending | pending |
| 200% | pending | pending | pending |
| 300% | pending | pending | pending |
| 400% | pending | pending | pending |

Reference reader should be Adobe Acrobat Reader or Microsoft Edge. Use one reference reader consistently for the complete matrix.

## Additional mandatory interaction captures

After the static matrix, collect evidence for:

1. pan at 200%
2. pan at 400%
3. window resize at 100%
4. maximize -> restore -> maximize at 100%
5. zoom transition 75% -> 200% -> 400% -> 100%

For zoom transitions, a temporarily scaled preview is acceptable only while interaction is active. The final settled frame must become sharp.

## Evidence directory convention

Store future evidence outside source control if it contains large binary screenshots, but use these logical names when recording the results:

- `lexpdf-075.png`
- `reference-075.png`
- `lexpdf-100.png`
- `reference-100.png`
- `lexpdf-125.png`
- `reference-125.png`
- `lexpdf-200.png`
- `reference-200.png`
- `lexpdf-300.png`
- `reference-300.png`
- `lexpdf-400.png`
- `reference-400.png`

The manifest at `apps/lexpdf_app/tool/render_core2_visual_baseline.json` records the evidence state without committing the screenshots themselves.

## Acceptance criteria for Phase 1

Phase 1 is complete only when:

- all six zoom levels have LexPDF and reference observations;
- the physical environment is recorded;
- the current LexPDF failure pattern is documented;
- pan and resize behavior are recorded;
- the comparison establishes whether the defect is resolution/scaling-specific, zoom-specific, or persistent at every zoom;
- a human reviewer marks the manifest `phase_1_approved: true`.

Phase 1 does **not** require the defect to be fixed. It requires a complete, reproducible baseline against which every Render Core 2 prototype will be judged.

## Stop rule

Do not implement the native renderer, Texture path, caching, scheduler, or new tile strategy until this gate is complete. The next phase is the coordinate/scale audit, but it remains blocked until the baseline is approved.
