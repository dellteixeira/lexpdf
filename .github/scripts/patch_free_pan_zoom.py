from pathlib import Path

screen = Path('apps/lexpdf_app/lib/src/screens/pdf_workspace_stylus_screen.dart')
source = screen.read_text(encoding='utf-8')

replacements = [
    (
        "  bool _loadingInk = false;\n  _PdfViewMode _viewMode = _PdfViewMode.continuous;\n",
        "  bool _loadingInk = false;\n  _PdfViewMode _viewMode = _PdfViewMode.continuous;\n  Offset? _zoomAnchorLocal;\n",
    ),
    (
        "                          panEnabled: _stylusMode == _StylusMode.note\n                              ? false\n                              : (!_inkMode || _mobile),\n                          scaleEnabled: _stylusMode == _StylusMode.note\n                              ? false\n                              : (!_inkMode || _mobile),\n",
        "                          // Keep the document freely movable on both axes.\n                          // The extra finite boundary makes even an underflowing\n                          // page movable instead of forcing it back to the center.\n                          panAxis: PanAxis.free,\n                          boundaryMargin: EdgeInsets.all(_mobile ? 320.0 : 120.0),\n                          panEnabled: _stylusMode == _StylusMode.note\n                              ? false\n                              : (!_inkMode || _mobile),\n                          scaleEnabled: _stylusMode == _StylusMode.note\n                              ? false\n                              : (!_inkMode || _mobile),\n                          onInteractionStart: (details) {\n                            _zoomAnchorLocal = details.localFocalPoint;\n                          },\n                          onInteractionUpdate: (details) {\n                            _zoomAnchorLocal = details.localFocalPoint;\n                          },\n                          onInteractionEnd: (_) {\n                            _syncZoomFromController();\n                          },\n",
    ),
    (
        "  Future<void> _setZoomPercent(int percent) async {\n    if (!_controller.isReady) return;\n    final target = (percent / 100).clamp(_controller.minScale, _controller.maxScale);\n    await _controller.setZoom(_controller.centerPosition, target);\n    _syncZoomFromController();\n  }\n",
        "  Offset _effectiveZoomLocalAnchor() {\n    final anchor = _zoomAnchorLocal;\n    if (anchor != null && anchor.dx.isFinite && anchor.dy.isFinite) {\n      return anchor;\n    }\n    return _controller.documentToLocal(_controller.centerPosition);\n  }\n\n  Future<void> _setZoomPercent(int percent) async {\n    if (!_controller.isReady) return;\n    final target = (percent / 100)\n        .clamp(_controller.minScale, _controller.maxScale)\n        .toDouble();\n    await _controller.zoomOnLocalPosition(\n      localPosition: _effectiveZoomLocalAnchor(),\n      newZoom: target,\n      duration: Duration.zero,\n    );\n    _syncZoomFromController();\n  }\n",
    ),
    (
        "  Future<void> _zoomIn() async {\n    if (!_controller.isReady) return;\n    await _controller.zoomUp();\n    _syncZoomFromController();\n  }\n\n  Future<void> _zoomOut() async {\n    if (!_controller.isReady) return;\n    await _controller.zoomDown();\n    _syncZoomFromController();\n  }\n",
        "  Future<void> _zoomIn() async {\n    if (!_controller.isReady) return;\n    await _controller.zoomUpOnLocalPosition(\n      localPosition: _effectiveZoomLocalAnchor(),\n    );\n    _syncZoomFromController();\n  }\n\n  Future<void> _zoomOut() async {\n    if (!_controller.isReady) return;\n    await _controller.zoomDownOnLocalPosition(\n      localPosition: _effectiveZoomLocalAnchor(),\n    );\n    _syncZoomFromController();\n  }\n",
    ),
]

for old, new in replacements:
    if new in source:
        continue
    if old not in source:
        raise SystemExit(f'Expected patch anchor not found:\n{old[:180]}')
    source = source.replace(old, new, 1)

screen.write_text(source, encoding='utf-8')

test = Path('apps/lexpdf_app/test/pdf_free_pan_zoom_contract_test.dart')
test.write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF viewer keeps free pan and focal-point zoom on touch devices', () {
    final source = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();

    expect(source, contains('panAxis: PanAxis.free'));
    expect(source, contains('boundaryMargin: EdgeInsets.all(_mobile ? 320.0 : 120.0)'));
    expect(source, contains('onInteractionStart: (details)'));
    expect(source, contains('onInteractionUpdate: (details)'));
    expect(source, contains('_zoomAnchorLocal = details.localFocalPoint'));
    expect(source, contains('_effectiveZoomLocalAnchor()'));
    expect(source, contains('zoomOnLocalPosition('));
    expect(source, contains('zoomUpOnLocalPosition('));
    expect(source, contains('zoomDownOnLocalPosition('));
    expect(source, isNot(contains('setZoom(_controller.centerPosition')));
  });
}
""",
    encoding='utf-8',
)
