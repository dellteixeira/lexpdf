import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/pdf/render_core2_scale_model.dart';

/// Returns the Windows build number from [Platform.operatingSystemVersion].
int? parseWindowsBuildNumber(String version) {
  final dotted = RegExp(r'10\.0\.(\d{5})').allMatches(version).toList();
  if (dotted.isNotEmpty) {
    return int.tryParse(dotted.last.group(1)!);
  }
  final named = RegExp(
    r'build\s*[:=]?\s*(\d{5})',
    caseSensitive: false,
  ).allMatches(version).toList();
  if (named.isNotEmpty) {
    return int.tryParse(named.last.group(1)!);
  }
  return null;
}

/// Historical name retained to avoid broad workspace churn.
///
/// On Windows 10 this enables the Render Core 2 replacement surface. Phase 7C
/// deliberately uses a single supersampled full-page raster rather than the
/// failed external-texture path or the legacy tiled composition path.
bool isWindows10ManualTileRenderingEnabled() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;

  final nativeOverride =
      Platform.environment['LEXPDF_WINDOWS10_NATIVE_TEXTURE'];
  if (nativeOverride == '1') return true;
  if (nativeOverride == '0') return false;

  final legacyOverride =
      Platform.environment['LEXPDF_WINDOWS10_TILED_RENDERING'];
  if (legacyOverride == '1') return true;
  if (legacyOverride == '0') return false;

  final build = parseWindowsBuildNumber(Platform.operatingSystemVersion);
  return build != null && build >= 10240 && build < 22000;
}

/// Windows 10 production PDF visual surface.
///
/// pdfrx remains responsible for layout/navigation/text-selection. The visible
/// page is rendered as one complete bitmap, never as independently positioned
/// tiles. The requested physical page size is computed from pageRect * DPR
/// exactly once and then adaptively supersampled to improve low-zoom text.
class Windows10PdfTileOverlay extends StatefulWidget {
  const Windows10PdfTileOverlay({
    required this.page,
    required this.pageRect,
    required this.controller,
    super.key,
  });

  final PdfPage page;
  final Rect pageRect;
  final PdfViewerController controller;

  @override
  State<Windows10PdfTileOverlay> createState() =>
      _Windows10PdfTileOverlayState();
}

class _Windows10PdfTileOverlayState extends State<Windows10PdfTileOverlay> {
  static const Duration _settleDelay = Duration(milliseconds: 55);
  static const int _maxRasterDimension = 8192;
  static const bool _showDiagnosticBadge = bool.fromEnvironment(
    'LEXPDF_RENDER_DIAGNOSTICS',
    defaultValue: true,
  );

  Timer? _settleTimer;
  int _generation = 0;
  ui.Image? _image;
  int? _sourceWidth;
  int? _sourceHeight;
  int? _targetWidth;
  int? _targetHeight;
  double? _supersample;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRefresh());
  }

  @override
  void didUpdateWidget(covariant Windows10PdfTileOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleRefresh);
      widget.controller.addListener(_scheduleRefresh);
    }
    if (oldWidget.page != widget.page) {
      _generation++;
      _disposeImage();
      _sourceWidth = null;
      _sourceHeight = null;
      _targetWidth = null;
      _targetHeight = null;
      _supersample = null;
      _error = null;
    }
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _generation++;
    _settleTimer?.cancel();
    widget.controller.removeListener(_scheduleRefresh);
    _disposeImage();
    super.dispose();
  }

  void _scheduleRefresh() {
    if (!mounted || !widget.controller.isReady) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () => unawaited(_refreshFullPage()));
  }

  double _chooseSupersample(int targetWidth, int targetHeight) {
    final longest = math.max(targetWidth, targetHeight);
    if (longest <= 1800) return 2.0;
    if (longest <= 3200) return 1.5;
    return 1.0;
  }

  Future<void> _refreshFullPage() async {
    if (!mounted || !widget.controller.isReady) return;

    final pageRect = widget.pageRect;
    if (pageRect.width <= 0 || pageRect.height <= 0) return;
    if (!widget.controller.visibleRect.overlaps(pageRect)) return;

    final dpr = View.of(context).devicePixelRatio;
    final scaleModel = RenderCore2ScaleModel.fromViewerRect(
      pageWidthPoints: widget.page.width,
      pageHeightPoints: widget.page.height,
      pageRectWidthLogical: pageRect.width,
      pageRectHeightLogical: pageRect.height,
      currentZoom: widget.controller.currentZoom,
      devicePixelRatio: dpr,
    );

    final targetWidth = scaleModel.targetPixelWidth;
    final targetHeight = scaleModel.targetPixelHeight;
    if (targetWidth <= 0 || targetHeight <= 0) return;

    var supersample = _chooseSupersample(targetWidth, targetHeight);
    final longestTarget = math.max(targetWidth, targetHeight);
    if (longestTarget * supersample > _maxRasterDimension) {
      supersample = _maxRasterDimension / longestTarget;
    }
    supersample = supersample.clamp(1.0, 2.0);

    final renderWidth = math.max(1, (targetWidth * supersample).ceil());
    final renderHeight = math.max(1, (targetHeight * supersample).ceil());

    if (_image != null &&
        _sourceWidth == renderWidth &&
        _sourceHeight == renderHeight &&
        _targetWidth == targetWidth &&
        _targetHeight == targetHeight &&
        _error == null) {
      return;
    }

    final generation = ++_generation;
    PdfImage? rendered;
    try {
      await widget.page.ensureLoaded();
      if (!mounted || generation != _generation) return;

      rendered = await widget.page.render(
        width: renderWidth,
        height: renderHeight,
        fullWidth: renderWidth.toDouble(),
        fullHeight: renderHeight.toDouble(),
        backgroundColor: 0xFFFFFFFF,
        flags: PdfPageRenderFlags.none,
      );
      if (rendered == null || !mounted || generation != _generation) {
        rendered?.dispose();
        return;
      }

      final decoded = await _decodeBgra(rendered);
      rendered.dispose();
      rendered = null;
      if (!mounted || generation != _generation) {
        decoded.dispose();
        return;
      }

      final previous = _image;
      setState(() {
        _image = decoded;
        _sourceWidth = renderWidth;
        _sourceHeight = renderHeight;
        _targetWidth = targetWidth;
        _targetHeight = targetHeight;
        _supersample = supersample;
        _error = null;
      });
      previous?.dispose();

      debugPrint(
        '[LexPDF][RenderCore2][fullpage] page=${widget.page.pageNumber} '
        'zoom=${widget.controller.currentZoom.toStringAsFixed(4)} '
        'dpr=${dpr.toStringAsFixed(3)} target=${targetWidth}x$targetHeight '
        'render=${renderWidth}x$renderHeight ss=${supersample.toStringAsFixed(2)}',
      );
    } catch (error) {
      rendered?.dispose();
      debugPrint('[LexPDF][RenderCore2][fullpage] ERROR $error');
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    }
  }

  Future<ui.Image> _decodeBgra(PdfImage rendered) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rendered.pixels,
      rendered.width,
      rendered.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
      rowBytes: rendered.width * 4,
    );
    return completer.future;
  }

  void _disposeImage() {
    _image?.dispose();
    _image = null;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.white,
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Render Core 2 full-page: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),
                ),
              )
            : image == null
                ? const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      RawImage(
                        image: image,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                      if (_showDiagnosticBadge)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.76),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Text(
                                'RC2 fullpage ${_sourceWidth ?? '-'}×${_sourceHeight ?? '-'} '
                                '→ ${_targetWidth ?? '-'}×${_targetHeight ?? '-'} '
                                '${(_supersample ?? 1).toStringAsFixed(2)}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
