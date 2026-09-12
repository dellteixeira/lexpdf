import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/render_core2_scale_model.dart';

void main() {
  group('Render Core 2 scale model', () {
    test('75% viewer rect uses DPR only for physical raster width', () {
      final sample = RenderCore2ScaleModel.fromViewerRect(
        pageWidthPoints: 600,
        pageHeightPoints: 800,
        pageRectWidthLogical: 450,
        pageRectHeightLogical: 600,
        currentZoom: 0.75,
        devicePixelRatio: 1,
      );

      expect(sample.targetPixelWidth, 450);
      expect(sample.targetPixelHeight, 600);
      expect(sample.legacyDoubleZoomPixelWidth, 338);
      expect(sample.legacyDoubleZoomPixelHeight, 450);
    });

    test('75% at 125% Windows display scale renders 563 physical pixels', () {
      final sample = RenderCore2ScaleModel.fromViewerRect(
        pageWidthPoints: 600,
        pageHeightPoints: 800,
        pageRectWidthLogical: 450,
        pageRectHeightLogical: 600,
        currentZoom: 0.75,
        devicePixelRatio: 1.25,
      );

      expect(sample.targetPixelWidth, 563);
      expect(sample.targetPixelHeight, 750);
      expect(sample.legacyDoubleZoomPixelWidth, 422);
    });

    test('200% viewer rect is not multiplied by currentZoom again', () {
      final sample = RenderCore2ScaleModel.fromViewerRect(
        pageWidthPoints: 600,
        pageHeightPoints: 800,
        pageRectWidthLogical: 1200,
        pageRectHeightLogical: 1600,
        currentZoom: 2,
        devicePixelRatio: 1,
      );

      expect(sample.targetPixelWidth, 1200);
      expect(sample.targetPixelHeight, 1600);
      expect(sample.legacyDoubleZoomPixelWidth, 2400);
      expect(sample.legacyDoubleZoomPixelHeight, 3200);
    });

    test('document-to-viewer scale stays explicit and separate from DPR', () {
      final sample = RenderCore2ScaleModel.fromViewerRect(
        pageWidthPoints: 595,
        pageHeightPoints: 842,
        pageRectWidthLogical: 743.75,
        pageRectHeightLogical: 1052.5,
        currentZoom: 1.25,
        devicePixelRatio: 1.5,
      );

      expect(sample.documentToViewerScaleX, closeTo(1.25, 1e-9));
      expect(sample.documentToViewerScaleY, closeTo(1.25, 1e-9));
      expect(sample.physicalPixelsPerPdfPointX, closeTo(1.875, 1e-9));
      expect(sample.targetPixelWidth, 1116);
      expect(sample.targetPixelHeight, 1579);
    });

    test('rejects invalid coordinate-space inputs', () {
      expect(
        () => RenderCore2ScaleModel.fromViewerRect(
          pageWidthPoints: 0,
          pageHeightPoints: 842,
          pageRectWidthLogical: 595,
          pageRectHeightLogical: 842,
          currentZoom: 1,
          devicePixelRatio: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => RenderCore2ScaleModel.fromViewerRect(
          pageWidthPoints: 595,
          pageHeightPoints: 842,
          pageRectWidthLogical: 595,
          pageRectHeightLogical: 842,
          currentZoom: 1,
          devicePixelRatio: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
