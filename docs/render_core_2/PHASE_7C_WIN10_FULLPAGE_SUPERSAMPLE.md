# Render Core 2 — Phase 7C: Windows 10 full-page supersampled fallback

The 75% physical test after PR #148 still failed: the PDF surface was almost entirely white while Flutter chrome and ink remained sharp. That result rules out the previous PixelBuffer stride/alpha/lifetime hypotheses as the primary cause on the affected Windows 10 machine.

Phase 7C therefore removes Flutter external textures from the affected Win10 production path. The viewer keeps pdfrx for layout/navigation/text selection and renders each visible page as one full-page PDFium raster through the pdfrx `PdfPage.render` API. This avoids both the legacy tiled composition and the custom Windows `PixelBufferTexture` bridge.

The full page is rendered from `pageRect logical size * DPR` exactly once, with adaptive supersampling for low and medium zooms. At 75% the raster is rendered at 2x the physical target and downsampled once by Flutter using high-quality filtering. At larger physical sizes the supersampling factor reduces to cap memory and render cost.

The stop rule remains unchanged: 75% must pass physically before the 100–400% matrix proceeds.
