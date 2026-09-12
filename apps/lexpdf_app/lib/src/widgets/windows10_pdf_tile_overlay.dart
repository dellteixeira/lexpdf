import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Since Render Core 2 production integration this gate no longer enables the
/// old Dart/ui.Image tile renderer. It enables the native PDFium -> Flutter
/// Texture surface on physical Windows 10 hosts.
bool isWindows10ManualTileRenderingEnabled() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;

  final nativeOverride =
      Platform.environment['LEXPDF_WINDOWS10_NATIVE_TEXTURE'];
  if (nativeOverride == '1') return true;
  if (nativeOverride == '0') return false;

  // Keep the old override compatible for existing diagnostic scripts.
  final legacyOverride =
      Platform.environment['LEXPDF_WINDOWS10_TILED_RENDERING'];
  if (legacyOverride == '1') return true;
  if (legacyOverride == '0') return false;

  final build = parseWindowsBuildNumber(Platform.operatingSystemVersion);
  return build != null && build >= 10240 && build < 22000;
}

/// Production Windows 10 PDF visual surface.
///
/// pdfrx remains responsible for document layout, navigation, links and text
/// selection. The visible page pixels are supplied by an independent native
/// PDFium texture rendered at pageRect logical pixels * DPR exactly once.
/// No page-sized byte array is decoded into ui.Image and no RawImage path is
/// used here.
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
  static const MethodChannel _channel =
      MethodChannel('lexpdf/render_core2_production_pdfium');
  static const Duration _settleDelay = Duration(milliseconds: 35);
  static int _nextTextureKey = 1;

  late final int _textureKey = _nextTextureKey++;
  Timer? _settleTimer;
  int _generation = 0;
  int? _textureId;
  int? _pixelWidth;
  int? _pixelHeight;
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
      _pixelWidth = null;
      _pixelHeight = null;
      _error = null;
    }
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _generation++;
    _settleTimer?.cancel();
    widget.controller.removeListener(_scheduleRefresh);
    unawaited(
      _channel.invokeMethod<void>(
        'disposeTexture',
        <String, Object?>{'textureKey': _textureKey},
      ),
    );
    super.dispose();
  }

  void _scheduleRefresh() {
    if (!mounted || !widget.controller.isReady) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () => unawaited(_refreshNativeTexture()));
  }

  Future<void> _refreshNativeTexture() async {
    if (!mounted || !widget.controller.isReady) return;
    final pageRect = widget.pageRect;
    if (pageRect.width <= 0 || pageRect.height <= 0) return;
    if (!widget.controller.visibleRect.overlaps(pageRect)) return;

    final sourceName = widget.page.document.sourceName;
    if (sourceName.isEmpty || sourceName.startsWith('memory:') ||
        sourceName.startsWith('asset:')) {
      if (mounted) {
        setState(() => _error = 'Render Core 2 requires a local PDF file path.');
      }
      return;
    }

    final dpr = View.of(context).devicePixelRatio;
    final scaleModel = RenderCore2ScaleModel.fromViewerRect(
      pageWidthPoints: widget.page.width,
      pageHeightPoints: widget.page.height,
      pageRectWidthLogical: pageRect.width,
      pageRectHeightLogical: pageRect.height,
      currentZoom: widget.controller.currentZoom,
      devicePixelRatio: dpr,
    );
    final width = scaleModel.targetPixelWidth;
    final height = scaleModel.targetPixelHeight;
    if (width <= 0 || height <= 0 || width > 32768 || height > 32768) {
      if (mounted) {
        setState(() => _error = 'Physical raster outside safety bounds: ${width}x$height.');
      }
      return;
    }

    // Panning does not require another raster when physical dimensions are
    // unchanged. Zoom/DPI/layout changes do.
    if (_textureId != null &&
        _pixelWidth == width &&
        _pixelHeight == height &&
        _error == null) {
      return;
    }

    final generation = ++_generation;
    try {
      final opened = await _channel.invokeMethod<bool>(
        'ensureDocument',
        <String, Object?>{'documentPath': sourceName},
      );
      if (opened != true || !mounted || generation != _generation) return;

      _textureId ??= await _channel.invokeMethod<int>(
        'createTexture',
        <String, Object?>{'textureKey': _textureKey},
      );
      if (_textureId == null || !mounted || generation != _generation) return;

      final result = await _channel.invokeMapMethod<String, Object?>(
        'renderPageToTexture',
        <String, Object?>{
          'textureKey': _textureKey,
          'pageNumber': widget.page.pageNumber,
          'pixelWidth': width,
          'pixelHeight': height,
          'generation': generation,
        },
      );
      if (!mounted || generation != _generation || result == null) return;

      final textureId = result['textureId'];
      final returnedWidth = result['width'];
      final returnedHeight = result['height'];
      final returnedGeneration = result['generation'];
      if (textureId is! int ||
          returnedWidth != width ||
          returnedHeight != height ||
          returnedGeneration != generation) {
        throw StateError('Native renderer did not honor the physical-pixel contract.');
      }

      debugPrint(
        '[LexPDF][RenderCore2][production] page=${widget.page.pageNumber} '
        'zoom=${widget.controller.currentZoom.toStringAsFixed(4)} '
        'dpr=${dpr.toStringAsFixed(3)} requested=${width}x$height '
        'returned=${returnedWidth}x$returnedHeight texture=$textureId',
      );
      setState(() {
        _textureId = textureId;
        _pixelWidth = width;
        _pixelHeight = height;
        _error = null;
      });
    } catch (error) {
      debugPrint('[LexPDF][RenderCore2][production] ERROR $error');
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        // Fail closed: never reveal the known-bad pdfrx backing raster on
        // Windows 10. If native rendering fails, show an explicit error.
        color: Colors.white,
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Render Core 2: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ),
              )
            : _textureId == null
                ? const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Texture(
                        textureId: _textureId!,
                        filterQuality: FilterQuality.none,
                      ),
                      if (kDebugMode)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Text(
                                'RC2 native ${_pixelWidth ?? '-'}×${_pixelHeight ?? '-'}',
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
