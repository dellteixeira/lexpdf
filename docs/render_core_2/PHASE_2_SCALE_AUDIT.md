# Render Core 2 — Phase 2: Coordinate and Scale Audit

Status: **STARTED**

Phase 2 was started after explicit project-owner instruction to advance despite the Phase 1 physical baseline matrix still being incomplete. The known physical evidence remains valid: the Windows 10 screenshot at 75% shows blurred/deformed PDF page pixels while Flutter chrome and ink remain sharp.

## Audit finding

The current Windows 10 tile overlay derives its raster scale from both:

- `pageRect` supplied by `PdfViewerParams.pageOverlaysBuilder`
- `controller.currentZoom`

The pdfrx API defines the overlay rectangle as the page rectangle **in the viewer**. It therefore already represents the viewer-space page geometry. Multiplying that viewer-space rectangle by `currentZoom` again mixes coordinate spaces and can under-render below 100% zoom and over-render above 100% zoom.

### Existing formula

```text
requestedScale = currentZoom * devicePixelRatio
fullWidth      = pageRect.width * requestedScale
```

Effective result:

```text
fullWidth = pageRect.width * currentZoom * DPR
```

Because `pageRect.width` is already the page width in viewer coordinates, `currentZoom` must not be applied again when deriving physical pixels from that rectangle.

### Render Core 2 formula

```text
physicalWidth  = ceil(pageRectInViewer.width  * DPR)
physicalHeight = ceil(pageRectInViewer.height * DPR)
```

`currentZoom` remains useful as telemetry and interaction state, but is not another multiplier in this conversion.

## Concrete 75% example

Assume:

```text
PDF page width      = 600 pt
viewer page width   = 450 logical px
currentZoom         = 0.75
DPR                 = 1.0
```

Correct physical target:

```text
450 * 1.0 = 450 px
```

Legacy double-zoom target:

```text
450 * 0.75 * 1.0 = 337.5 -> 338 px
```

That legacy raster is then displayed across a 450 logical-pixel page, forcing upsampling and providing a plausible mechanism for the severe blur observed at 75%.

At 200%, the same error goes in the opposite direction: it can request roughly twice the already-zoomed viewer geometry, wasting memory and render time.

## Coordinate spaces

Render Core 2 formally separates three spaces:

1. **PDF space** — page points and PDF-native geometry.
2. **Viewer logical space** — Flutter/pdfrx layout coordinates, including viewer layout scale/zoom.
3. **Physical pixel space** — raster dimensions after applying the display DPR exactly once.

No value may cross these spaces without an explicit conversion.

## Code added in this phase

`RenderCore2ScaleModel` codifies the conversion and exposes the legacy double-zoom result only for diagnostics/regression tests.

Tests cover:

- 75% zoom at DPR 1.0
- 75% zoom at Windows 125% display scale
- 200% zoom without applying zoom twice
- explicit document-to-viewer and viewer-to-physical separation
- invalid input rejection

## Phase 2 exit criteria

Before Phase 3 begins:

- [x] Identify the coordinate-space contract.
- [x] Isolate the double-zoom hypothesis in executable tests.
- [x] Define the correct viewer-logical -> physical-pixel conversion.
- [ ] Instrument or replace the current renderer so the production path uses this model.
- [ ] Verify CI on the exact branch HEAD.

The last two items will be completed before Phase 2 is marked complete.
