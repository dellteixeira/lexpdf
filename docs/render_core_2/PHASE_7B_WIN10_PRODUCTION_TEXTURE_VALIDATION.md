# Render Core 2 — Phase 7B: Windows 10 Production Texture Validation

Status: **BLOCKED — physical Windows 10 evidence required**

Production base: `abdfdeaa2ae8b4c0fa1fe2f19a3ed13a120cb191`

Renderer integration: PR #146, head `6f952a913e818ac99b8fbeedcc7fb301e22affea`.

## Why Phase 7B exists

The original Phase 7 physical test at 75% failed: the PDF page remained severely blurred while Flutter chrome and blue ink were sharp. The investigation showed that the native PDFium Texture renderer existed, but the production workspace was still executing the legacy `PdfPage.render -> decodeImageFromPixels -> ui.Image -> RawImage` surface.

PR #146 replaced that production Windows 10 visual surface with native PDFium `PixelBufferTexture` rendering. Phase 7B validates the actual production workspace, not the standalone diagnostic.

## Gate order

Do **not** run the full matrix immediately. First validate 75% on the same physical Windows 10 machine and the same reproducer PDF:

`tratado_leis_especiais_concursos_2026_atualizado_15-08-2026.pdf`

At 75%, the screenshot must show the normal LexPDF workspace and, in a debug build, the visible renderer badge beginning with:

`RC2 native`

The application log should contain entries beginning with:

`[LexPDF][RenderCore2][production]`

If the badge is absent, the test is invalid because it does not prove that the new production renderer is active.

## 75% acceptance criteria

The 75% gate passes only when all of the following are true:

1. the normal production workspace is being tested;
2. the `RC2 native` badge is visible in a debug build;
3. the PDF text/vector content is materially sharper than the prior failed capture;
4. the page does not exhibit vertical smearing, stretched raster artifacts, black frames or stale texture contents;
5. requested physical dimensions equal the returned native texture dimensions;
6. Flutter chrome and ink remain correctly aligned with the page;
7. no legacy `RawImage` / `decodeImageFromPixels` page surface is involved.

If any item fails, stop and return to renderer diagnostics. Do not continue the matrix.

## Full matrix after 75% passes

Then validate 100%, 125%, 200%, 300% and 400%. Use one reference application consistently: Adobe Acrobat Reader preferred, or Microsoft Edge if Acrobat is unavailable.

For each zoom capture:

- full LexPDF screenshot;
- 100% crop of a representative text/vector region;
- same region in the reference application;
- renderer badge/log evidence;
- requested and returned physical dimensions;
- PASS/FAIL notes.

## Interaction matrix

After all zoom levels pass, validate:

- pan at 200%;
- pan at 400%;
- resize at 100%;
- maximize -> restore -> maximize at 100%;
- zoom sequence 75% -> 200% -> 400% -> 100%;
- previous/next page navigation.

No stale generation, black frame, frozen texture, corruption or crash is allowed.

## Stop rule

CI and a successful Windows release build prove that the native implementation compiles and packages. They do **not** prove visual sharpness on the affected Windows 10 machine. Phase 7B remains unapproved until physical 75% evidence passes, followed by the full zoom and interaction matrix.
