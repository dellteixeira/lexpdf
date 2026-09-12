# Render Core 2 — Phase 3: isolated prototype boundary

## Goal

Create a strict seam between the current pdfrx-based viewer and the future native Windows renderer before any PDFium-native implementation is introduced.

## Rules

- The existing viewer remains the production path.
- The native prototype is opt-in only through `LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE`.
- The native prototype may activate only on Windows.
- Android, iOS and other platforms must continue to resolve to the existing viewer.
- Phase 3 must not change user-visible rendering yet.
- No PDFium FFI/native plugin is added in this phase.

## New contract

`LexPdfRenderSurface` is the boundary the future native renderer must implement.

The request object carries physical raster dimensions explicitly:

- document path
- page number
- pixel width
- pixel height
- device pixel ratio
- viewer zoom as diagnostic context
- generation token for stale-render cancellation

The render result is deliberately backend-neutral and exposes a BGRA8888 frame contract for the first prototype. Phase 6 may replace the transfer path with a Flutter Texture/native surface while keeping the higher-level renderer boundary stable.

## Exit criteria

Phase 3 is complete when:

1. production behavior is unchanged by default;
2. backend selection is deterministic and test-covered;
3. the future native renderer has a stable interface independent of the workspace UI;
4. non-Windows platforms cannot accidentally activate the prototype;
5. CI is green on the exact branch head.

After this gate passes, Phase 4 may implement a minimal Windows native PDFium backend behind this boundary.
