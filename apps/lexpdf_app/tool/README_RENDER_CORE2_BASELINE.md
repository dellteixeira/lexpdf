# Render Core 2 — Physical Baseline Collection

Use the physical Windows 10 machine that reproduces the LexPDF blur/deformation defect.

## Required static captures

Open the same test PDF in LexPDF and in one reference reader (Adobe Acrobat Reader or Microsoft Edge). Keep the machine, monitor, display resolution, Windows display scaling, page, and viewport as consistent as possible.

Capture both applications at:

- 75%
- 100%
- 125%
- 200%
- 300%
- 400%

For every row, record an observation and evidence identifier/path in `render_core2_visual_baseline.json`.

## Required interaction observations

Record the settled visual result after:

- pan at 200%
- pan at 400%
- resize at 100%
- maximize -> restore -> maximize at 100%
- zoom 75% -> 200% -> 400% -> 100%

Temporary blur while the user is actively zooming may be recorded separately. The important result is whether the final settled frame becomes sharp.

## Environment fields

Fill every environment field in the manifest. `monitor_model` is optional; all other listed fields are required by the validator.

## Gate command

```bash
python tool/validate_render_core2_visual_baseline.py
```

Expected result while evidence is incomplete:

```text
Render Core 2 Phase 1 gate: BLOCKED
```

Only after all evidence is complete and reviewed should `phase_1_approved` be changed to `true`. A successful validator result unlocks Phase 2.
