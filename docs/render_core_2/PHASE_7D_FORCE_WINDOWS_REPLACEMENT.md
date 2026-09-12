# Phase 7D — Force Windows replacement renderer

The PR #149 physical test at 75% still failed. More importantly, the screenshot did not show the `RC2 fullpage ...` badge that is rendered in the same widget stack as the Phase 7C replacement surface and is enabled by default in release builds.

That makes the previous test path ambiguous: the replacement renderer was not active in the captured run.

Phase 7D removes the Windows build-number decision from the renderer gate. On native Windows the replacement surface is now enabled by default; only an explicit environment opt-out (`LEXPDF_WINDOWS10_NATIVE_TEXTURE=0` or legacy `LEXPDF_WINDOWS10_TILED_RENDERING=0`) disables it. The build parser remains available for diagnostics and tests but no longer controls the visible PDF renderer.

Exit condition remains unchanged: validate the same PDF at 75% physically and require the `RC2 fullpage ...` badge to be visible. If the badge is visible and the PDF still smears, the failure is inside the full-page `PdfPage.render`/decode/presentation path. If the badge is absent, the test is invalid because a different renderer is executing.
