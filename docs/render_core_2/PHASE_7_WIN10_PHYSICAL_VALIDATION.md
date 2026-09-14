# Render Core 2 — Phase 7: Windows 10 Physical Validation

Status: **BLOCKED — physical evidence required**

Base implementation: `387ee71ce341374d9e9104f98974495822f0f601`

This phase does not add renderer features. It validates the native PDFium + Flutter Texture path on real Windows 10 hardware before any workspace integration.

## Fixed reproducer

Use the same PDF that exposed the original blur defect:

`tratado_leis_especiais_concursos_2026_atualizado_15-08-2026.pdf`

Run the standalone diagnostic from `apps/lexpdf_app`:

```bash
flutter run -d windows -t lib/render_core2_diagnostic_main.dart --dart-define=LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE=true
```

## Reference application

Use one reference application consistently for the complete matrix:

- Adobe Acrobat Reader, preferred; or
- Microsoft Edge, if Acrobat is unavailable.

Do not mix reference applications inside the same evidence matrix.

## Mandatory zoom matrix

Capture LexPDF Render Core 2 and the reference application at:

- 75%
- 100%
- 125%
- 200%
- 300%
- 400%

For every zoom, record:

1. full application screenshot;
2. 100% crop of the same text/vector region from LexPDF;
3. 100% crop of the same region from the reference application;
4. diagnostic footer showing PDF points, zoom, DPR, requested pixels and returned pixels;
5. PASS/FAIL assessment.

## Interaction checks

The following must also pass without blur regression, stale frames, corruption or crashes:

- pan at 200%;
- pan at 400%;
- resize at 100%;
- maximize → restore → maximize at 100%;
- zoom sequence 75% → 200% → 400% → 100%;
- page previous/next navigation.

## Acceptance criteria

Phase 7 passes only if all of the following are true:

- text and vector edges are materially comparable to the reference application at every mandatory zoom;
- no severe softness like the original Windows 10 75% failure is visible;
- requested physical pixel dimensions equal the returned dimensions;
- no additional `RawImage`/`decodeImageFromPixels` path is involved in the diagnostic presentation;
- no stale generation is presented after rapid zoom/page changes;
- no crash, black frame, frozen texture or unrecoverable blank page occurs;
- the same test PDF and Windows 10 machine are used for the full matrix.

## Stop rule

Do not integrate the native renderer into the production workspace until this phase is physically approved.

If any zoom fails, record the failure exactly and return to renderer diagnostics. Do not mark the phase complete based on CI alone.
