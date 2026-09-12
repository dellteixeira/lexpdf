import 'dart:math' as math;

/// Coordinate/scale model used by Render Core 2.
///
/// pdfrx pageOverlaysBuilder supplies [pageRectInViewer] in viewer coordinates.
/// That rectangle already reflects the viewer layout/zoom. Therefore the
/// physical raster target derived from that rectangle must multiply by DPR
/// only; currentZoom is diagnostic context and must not be multiplied again.
class RenderCore2ScaleModel {
  const RenderCore2ScaleModel._();

  static RenderCore2ScaleSample fromViewerRect({
    required double pageWidthPoints,
    required double pageHeightPoints,
    required double pageRectWidthLogical,
    required double pageRectHeightLogical,
    required double currentZoom,
    required double devicePixelRatio,
  }) {
    if (pageWidthPoints <= 0 || pageHeightPoints <= 0) {
      throw ArgumentError('PDF page dimensions must be positive.');
    }
    if (pageRectWidthLogical <= 0 || pageRectHeightLogical <= 0) {
      throw ArgumentError('Viewer page rectangle dimensions must be positive.');
    }
    if (currentZoom <= 0) {
      throw ArgumentError.value(currentZoom, 'currentZoom', 'must be positive');
    }
    if (devicePixelRatio <= 0) {
      throw ArgumentError.value(
        devicePixelRatio,
        'devicePixelRatio',
        'must be positive',
      );
    }

    final documentToViewerScaleX = pageRectWidthLogical / pageWidthPoints;
    final documentToViewerScaleY = pageRectHeightLogical / pageHeightPoints;
    final physicalPixelsPerViewerLogicalPixel = devicePixelRatio;

    return RenderCore2ScaleSample(
      pageWidthPoints: pageWidthPoints,
      pageHeightPoints: pageHeightPoints,
      pageRectWidthLogical: pageRectWidthLogical,
      pageRectHeightLogical: pageRectHeightLogical,
      currentZoom: currentZoom,
      devicePixelRatio: devicePixelRatio,
      documentToViewerScaleX: documentToViewerScaleX,
      documentToViewerScaleY: documentToViewerScaleY,
      targetPixelWidth: math.max(
        1,
        (pageRectWidthLogical * physicalPixelsPerViewerLogicalPixel).ceil(),
      ),
      targetPixelHeight: math.max(
        1,
        (pageRectHeightLogical * physicalPixelsPerViewerLogicalPixel).ceil(),
      ),
    );
  }
}

class RenderCore2ScaleSample {
  const RenderCore2ScaleSample({
    required this.pageWidthPoints,
    required this.pageHeightPoints,
    required this.pageRectWidthLogical,
    required this.pageRectHeightLogical,
    required this.currentZoom,
    required this.devicePixelRatio,
    required this.documentToViewerScaleX,
    required this.documentToViewerScaleY,
    required this.targetPixelWidth,
    required this.targetPixelHeight,
  });

  final double pageWidthPoints;
  final double pageHeightPoints;
  final double pageRectWidthLogical;
  final double pageRectHeightLogical;
  final double currentZoom;
  final double devicePixelRatio;
  final double documentToViewerScaleX;
  final double documentToViewerScaleY;
  final int targetPixelWidth;
  final int targetPixelHeight;

  double get physicalPixelsPerPdfPointX =>
      documentToViewerScaleX * devicePixelRatio;

  double get physicalPixelsPerPdfPointY =>
      documentToViewerScaleY * devicePixelRatio;

  /// Returns the incorrect width produced by the abandoned double-zoom model.
  /// Kept only for diagnostics and regression tests.
  int get legacyDoubleZoomPixelWidth => math.max(
        1,
        (pageRectWidthLogical * currentZoom * devicePixelRatio).ceil(),
      );

  /// Returns the incorrect height produced by the abandoned double-zoom model.
  int get legacyDoubleZoomPixelHeight => math.max(
        1,
        (pageRectHeightLogical * currentZoom * devicePixelRatio).ceil(),
      );
}
