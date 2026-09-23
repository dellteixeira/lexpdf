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

  /// Delay the initial overlay hydration until the first viewer frame settles.
  static const Duration initialOverlayLoadDelay = Duration(milliseconds: 160);

  /// Coalesce fast page changes so scrolling through thousands of pages does
  /// not trigger storage/text work for every intermediate page.
  static const Duration overlayPageChangeDebounce = Duration(milliseconds: 90);

  /// Absolute compatibility ceiling for mobile render cache.
  ///
  /// The active reader uses [viewerImageCacheBytesFor] so the actual budget is
  /// normally lower on large PDFs and/or smaller viewports.
  static const int viewerImageCacheBytes = 64 * 1024 * 1024;

  static const int _mobileViewerCacheMinBytes = 12 * 1024 * 1024;
  static const int _mobileViewerCacheUnknownMaxBytes = 20 * 1024 * 1024;
  static const int _mobileViewerCacheNormalMaxBytes = 32 * 1024 * 1024;
  static const int _mobileViewerCacheLargeMaxBytes = 24 * 1024 * 1024;
  static const int _mobileViewerCacheHugeMaxBytes = 16 * 1024 * 1024;
  static const int _mobileRecoveryCacheMaxBytes = 12 * 1024 * 1024;
  static const int _mobileEmergencyCacheMaxBytes = 8 * 1024 * 1024;
  static const int androidLargePdfPageThreshold = 1000;
  static const int androidLargePdfFileBytes = 50 * 1024 * 1024;
  static const int _windowsViewerCacheMinBytes = 64 * 1024 * 1024;
  static const int _windowsViewerCacheMaxBytes = 100 * 1024 * 1024;
  static const int _windowsViewerCacheLargeMaxBytes = 84 * 1024 * 1024;
  static const int _windowsViewerCacheHugeMaxBytes = 72 * 1024 * 1024;


  /// Android reader profile modeled after mature tile-based readers: keep the
  /// initial full-page raster small, render only a narrow neighborhood and
  /// delay expensive secondary work until the first page has settled.
  static const double androidOnePassRenderingSizeThreshold = 900;
  static const double androidMaxRenderLongEdge = 2200;
  static const double androidCacheExtent = 0.12;
  static const Duration androidTrailingPageLoadingDelay =
      Duration(milliseconds: 450);
  static const Duration androidPageImageCachingDelay =
      Duration(milliseconds: 90);
  static const Duration androidPartialImageLoadingDelay =
      Duration(milliseconds: 180);
  static const Duration androidSecondaryWorkDelay =
      Duration(milliseconds: 1200);
  static const Duration androidRecoverySecondaryWorkDelay =
      Duration(seconds: 6);
  static const Duration androidStableOpenWindow = Duration(seconds: 8);
  static const double androidRecoveryOnePassRenderingSizeThreshold = 700;
  static const double androidEmergencyOnePassRenderingSizeThreshold = 512;
  static const double androidRecoveryMaxRenderLongEdge = 1600;
  static const double androidEmergencyMaxRenderLongEdge = 1200;
  static const double androidRecoveryCacheExtent = 0.04;
  static const double androidEmergencyCacheExtent = 0.0;

  /// Returns a bounded render-cache budget using the visible viewport as the
  /// working-set estimate and the total page count as a memory-pressure hint.
  ///
  /// This deliberately avoids scaling cache memory with document length. A
  /// 5,000-page document should keep only a few visible/nearby rasters alive,
  /// while a 100-page document may use a slightly larger cache for smoother
  /// back-and-forth navigation.
  static int viewerImageCacheBytesFor({
    required bool isWindows,
    required int pageCount,
    required double viewportWidth,
    required double viewportHeight,
    required double devicePixelRatio,
    int androidRecoveryLevel = 0,
  }) {
    final safeWidth = math.max(1.0, viewportWidth);
    final safeHeight = math.max(1.0, viewportHeight);
    final safeDpr = devicePixelRatio.clamp(1.0, 3.0).toDouble();

    // RGBA estimate for one full viewport. pdfrx does not necessarily allocate
    // this exact shape for every page, but it is a stable upper-bound proxy for
    // how much visible raster data the device is likely to keep hot.
    final viewportBytes =
        safeWidth * safeHeight * safeDpr * safeDpr * 4.0;
    final targetViewports = isWindows ? 4.0 : 2.0;
    final requested = (viewportBytes * targetViewports).round();

    if (!isWindows && androidRecoveryLevel > 0) {
      final cap = androidRecoveryLevel >= 2
          ? _mobileEmergencyCacheMaxBytes
          : _mobileRecoveryCacheMaxBytes;
      final floor = math.min(8 * 1024 * 1024, cap);
      return requested.clamp(floor, cap).toInt();
    }

    final minBytes =
        isWindows ? _windowsViewerCacheMinBytes : _mobileViewerCacheMinBytes;
    final maxBytes = switch (pageCount) {
      <= 0 => isWindows
          ? _windowsViewerCacheLargeMaxBytes
          : _mobileViewerCacheUnknownMaxBytes,
      >= 3000 => isWindows
          ? _windowsViewerCacheHugeMaxBytes
          : _mobileViewerCacheHugeMaxBytes,
      >= 1000 => isWindows
          ? _windowsViewerCacheLargeMaxBytes
          : _mobileViewerCacheLargeMaxBytes,
      _ => isWindows
          ? _windowsViewerCacheMaxBytes
          : _mobileViewerCacheNormalMaxBytes,
    };

    return requested.clamp(minBytes, maxBytes).toInt();
  }

  static double androidOnePassThresholdForRecovery(int recoveryLevel) {
    if (recoveryLevel >= 2) {
      return androidEmergencyOnePassRenderingSizeThreshold;
    }
    if (recoveryLevel == 1) {
      return androidRecoveryOnePassRenderingSizeThreshold;
    }
    return androidOnePassRenderingSizeThreshold;
  }

  static double androidMaxRenderLongEdgeForRecovery(int recoveryLevel) {
    if (recoveryLevel >= 2) return androidEmergencyMaxRenderLongEdge;
    if (recoveryLevel == 1) return androidRecoveryMaxRenderLongEdge;
    return androidMaxRenderLongEdge;
  }

  static double androidCacheExtentForRecovery(int recoveryLevel) {
    if (recoveryLevel >= 2) return androidEmergencyCacheExtent;
    if (recoveryLevel == 1) return androidRecoveryCacheExtent;
    return androidCacheExtent;
  }


  static bool isLargeAndroidPdf({
    required int pageCount,
    required int fileSizeBytes,
  }) {
    return pageCount >= androidLargePdfPageThreshold ||
        fileSizeBytes >= androidLargePdfFileBytes;
  }

  static bool shouldUseAndroidSafeLocalOpen({
    required int recoveryLevel,
    required int fileSizeBytes,
  }) {
    return recoveryLevel > 0 || fileSizeBytes >= androidLargePdfFileBytes;
  }

  /// Automatic indexing starts with only a small neighborhood around the
  /// page the user is actually reading. This bounds duplicate PDF work while
  /// still making nearby search/navigation useful immediately.
  static const int localizedIndexPagesBefore = 3;
  static const int localizedIndexPagesAfter = 6;

  /// Broader automatic indexing is allowed only after the reader has remained
  /// idle for this long. Each idle pass is intentionally small so a pointer,
  /// scroll, zoom or page-navigation event can stop the next pass quickly.
  static const Duration backgroundIndexIdleDelay = Duration(seconds: 5);
  static const int idleIndexChunkPages = 6;

  /// OCR bitmap budget. Mobile/native bitmap OCR is capped at 8 MP, while
  /// desktop OCR is capped at 6 MP because the platform bridge also needs an
  /// encoded image buffer. This keeps the peak per-page working set bounded.
  static const int ocrMaxPixels = 1500000;
  static const int ocrDesktopMaxPixels = 6 * 1024 * 1024;
  static const int ocrMaxDimension = 1600;
  static const double ocrPreferredScale = 2.0;

  /// If a page already exposes enough embedded text, prefer it over raster OCR.
  /// This makes born-digital 2,000–5,000 page documents dramatically faster and
  /// avoids allocating a bitmap for pages that do not need OCR at all.
  static const int ocrEmbeddedTextMinChars = 24;

  /// Work in small batches so the event loop/UI gets opportunities to run.
  static const int ocrYieldEveryPages = 1;

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

  static ({int start, int end}) localizedIndexWindow({
    required int pageNumber,
    required int pageCount,
  }) {
    if (pageCount <= 0) return (start: 1, end: 0);
    final current = pageNumber.clamp(1, pageCount);
    return (
      start: math.max(1, current - localizedIndexPagesBefore),
      end: math.min(pageCount, current + localizedIndexPagesAfter),
    );
  }

  static ({int start, int end})? nextIdleIndexWindow({
    required int pageNumber,
    required int pageCount,
    required Set<int> processedPages,
  }) {
    if (pageCount <= 0 || processedPages.length >= pageCount) return null;
    final current = pageNumber.clamp(1, pageCount);

    int? lower;
    int? upper;
    for (var distance = 0; distance < pageCount; distance++) {
      final candidateLower = current - distance;
      if (lower == null &&
          candidateLower >= 1 &&
          !processedPages.contains(candidateLower)) {
        lower = candidateLower;
      }

      final candidateUpper = current + distance;
      if (upper == null &&
          candidateUpper <= pageCount &&
          !processedPages.contains(candidateUpper)) {
        upper = candidateUpper;
      }

      if (lower != null || upper != null) break;
    }

    if (lower == null && upper == null) return null;
    final lowerDistance = lower == null ? pageCount + 1 : current - lower;
    final upperDistance = upper == null ? pageCount + 1 : upper - current;

    if (lower != null && lowerDistance <= upperDistance) {
      return (
        start: math.max(1, lower - idleIndexChunkPages + 1),
        end: lower,
      );
    }

    final start = upper!;
    return (
      start: start,
      end: math.min(pageCount, start + idleIndexChunkPages - 1),
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
