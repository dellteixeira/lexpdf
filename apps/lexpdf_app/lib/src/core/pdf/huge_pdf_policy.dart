import 'dart:math' as math;

/// Centralized resource budgets for very large PDFs.
///
/// The goal is to keep memory usage bounded by the visible/active work rather
/// than by the total number of pages in a document.
class HugePdfPolicy {
  const HugePdfPolicy._();

  /// Reader overlays are hydrated only around the current page.
  static const int overlayPagesBefore = 2;
  static const int overlayPagesAfter = 3;

  /// Keep the rendered image cache bounded even for 2,000–5,000+ page files.
  static const int viewerImageCacheBytes = 64 * 1024 * 1024;

  /// OCR bitmap budget. Mobile/native bitmap OCR is capped at 8 MP, while
  /// desktop OCR is capped at 6 MP because the platform bridge also needs an
  /// encoded image buffer. This keeps the peak per-page working set bounded.
  static const int ocrMaxPixels = 8 * 1024 * 1024;
  static const int ocrDesktopMaxPixels = 6 * 1024 * 1024;
  static const int ocrMaxDimension = 3072;
  static const double ocrPreferredScale = 2.0;

  /// If a page already exposes enough embedded text, prefer it over raster OCR.
  /// This makes born-digital 2,000–5,000 page documents dramatically faster and
  /// avoids allocating a bitmap for pages that do not need OCR at all.
  static const int ocrEmbeddedTextMinChars = 24;

  /// Work in small batches so the event loop/UI gets opportunities to run.
  static const int ocrYieldEveryPages = 2;

  static ({int width, int height}) boundedRenderSize({
    required double pageWidth,
    required double pageHeight,
    double preferredScale = ocrPreferredScale,
    int maxPixels = ocrMaxPixels,
    int maxDimension = ocrMaxDimension,
  }) {
    if (pageWidth <= 0 || pageHeight <= 0) {
      return (width: 1, height: 1);
    }

    var scale = preferredScale;
    final preferredPixels = pageWidth * pageHeight * scale * scale;
    if (preferredPixels > maxPixels) {
      scale = math.sqrt(maxPixels / (pageWidth * pageHeight));
    }
    scale = math.min(scale, maxDimension / pageWidth);
    scale = math.min(scale, maxDimension / pageHeight);
    scale = math.max(scale, 0.1);

    return (
      width: math.max(1, (pageWidth * scale).round()),
      height: math.max(1, (pageHeight * scale).round()),
    );
  }

  static ({int start, int end}) overlayWindow({
    required int pageNumber,
    required int pageCount,
  }) {
    if (pageCount <= 0) return (start: 1, end: 0);
    final current = pageNumber.clamp(1, pageCount);
    return (
      start: math.max(1, current - overlayPagesBefore),
      end: math.min(pageCount, current + overlayPagesAfter),
    );
  }
}
