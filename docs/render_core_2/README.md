# LexPDF Render Core 2

Render Core 2 now has two separate gates:

1. **implementation/CI gate** — native Windows surface, exact physical geometry, stale-render cancellation, bounded cache and diagnostics must compile and pass automated contracts;
2. **physical visual gate** — the affected Windows 10/11 machines must still be inspected at 75%, 100%, 125%, 200%, 300% and 400%.

CI is necessary but cannot certify perceived sharpness on a real monitor.

## Production Windows path

The current production path is:

`pdfrx layout/navigation -> WindowsNativePdfSurface -> Windows.Data.Pdf -> WIC -> exact 1:1 GDI child HWND`

PDF page pixels are not presented through Flutter `ui.Image`, `RawImage` or a bilinear Flutter texture.

## Hardening now present

- exact physical bounds derived from Flutter logical geometry × DPR;
- asynchronous native rendering;
- generation-based stale-render cancellation during fast scroll/zoom/resize;
- memory-bounded **128 MiB LRU** cache keyed by document/page/physical size;
- exact-size presentation through `SetDIBitsToDevice`; no `StretchDIBits`;
- diagnostics counters for render requests, cache hits/misses, stale discards, failures, total render time, cache bytes and cache entries;
- explicit native badge during the physical validation cycle.

The LRU intentionally caches only exact-size frames. It never rescales a cached frame to satisfy a new geometry, because doing that would recreate the blur path this renderer was designed to remove.

## Physical validation protocol

The release gate remains pending until a real Windows machine records:

- 75%, 100%, 125%, 200%, 300%, 400%;
- pan at 200% and 400%;
- resize at 100%;
- maximize → restore → maximize;
- 75% → 200% → 400% → 100%;
- at least one display-scale transition when multiple DPI monitors are available.

For each case, compare with a reference reader using the same PDF/page and record whether text edges, glyph shape and line spacing remain sharp and geometrically stable.

The old `tool/render_core2_visual_baseline.json` remains historical evidence of the original failure and must not be rewritten as a pass without new physical evidence.

## Remaining external gate

The code can be merged when CI is green, but **Render Core 2 visual acceptance is not complete until physical evidence is supplied**. Do not claim a Windows sharpness pass from CI alone.
