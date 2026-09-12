import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// A true native Windows PDF surface.
///
/// Unlike the previous Render Core 2 experiments, this widget does not ask
/// Flutter to display PDF pixels at all. It only reports the page's physical
/// screen rectangle to the Win32 runner. The runner creates a child HWND and
/// renders the page with Windows.Data.Pdf -> WIC -> GDI directly into that HWND.
///
/// pdfrx remains underneath temporarily to preserve document layout, page
/// navigation and page rectangles during the Phase 7E rendering proof. The
/// native child window is mouse-transparent, so the existing viewer can still
/// receive navigation gestures. Annotation composition will be reintegrated
/// only after physical sharpness is proven.
class WindowsNativePdfSurface extends StatefulWidget {
  const WindowsNativePdfSurface({
    required this.documentPath,
    required this.page,
    required this.pageRect,
    required this.controller,
    super.key,
  });

  final String documentPath;
  final PdfPage page;
  final Rect pageRect;
  final PdfViewerController controller;

  @override
  State<WindowsNativePdfSurface> createState() =>
      _WindowsNativePdfSurfaceState();
}

class _WindowsNativePdfSurfaceState extends State<WindowsNativePdfSurface> {
  static const MethodChannel _channel =
      MethodChannel('lexpdf/windows_native_pdf');
  static int _nextSurfaceKey = 1;

  late final int _surfaceKey = _nextSurfaceKey++;
  Timer? _settleTimer;
  bool _disposed = false;
  int _lastX = -1;
  int _lastY = -1;
  int _lastWidth = -1;
  int _lastHeight = -1;
  int _lastPage = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleSync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleSync());
  }

  @override
  void didUpdateWidget(covariant WindowsNativePdfSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleSync);
      widget.controller.addListener(_scheduleSync);
    }
    if (oldWidget.documentPath != widget.documentPath ||
        oldWidget.page.pageNumber != widget.page.pageNumber) {
      _lastPage = -1;
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    widget.controller.removeListener(_scheduleSync);
    unawaited(
      _channel.invokeMethod<void>(
        'disposeSurface',
        <String, Object?>{'surfaceKey': _surfaceKey},
      ),
    );
    super.dispose();
  }

  void _scheduleSync() {
    if (!mounted || _disposed) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(
      const Duration(milliseconds: 20),
      () => WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncNativeSurface());
      }),
    );
  }

  Future<void> _syncNativeSurface() async {
    if (!mounted || _disposed || !widget.controller.isReady) return;

    if (!widget.controller.visibleRect.overlaps(widget.pageRect)) {
      await _channel.invokeMethod<void>(
        'hideSurface',
        <String, Object?>{'surfaceKey': _surfaceKey},
      );
      return;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final logicalOrigin = renderObject.localToGlobal(Offset.zero);
    final logicalSize = renderObject.size;
    final dpr = View.of(context).devicePixelRatio;

    final x = (logicalOrigin.dx * dpr).round();
    final y = (logicalOrigin.dy * dpr).round();
    final width = (logicalSize.width * dpr).round();
    final height = (logicalSize.height * dpr).round();
    if (width <= 0 || height <= 0) return;

    final pageNumber = widget.page.pageNumber;
    if (_lastX == x &&
        _lastY == y &&
        _lastWidth == width &&
        _lastHeight == height &&
        _lastPage == pageNumber) {
      return;
    }

    _lastX = x;
    _lastY = y;
    _lastWidth = width;
    _lastHeight = height;
    _lastPage = pageNumber;

    try {
      await _channel.invokeMethod<bool>(
        'showPage',
        <String, Object?>{
          'surfaceKey': _surfaceKey,
          'documentPath': widget.documentPath,
          'pageNumber': pageNumber,
          'x': x,
          'y': y,
          'width': width,
          'height': height,
        },
      );
      debugPrint(
        '[LexPDF][WinPDF] page=$pageNumber bounds=$x,$y ${width}x$height '
        'dpr=${dpr.toStringAsFixed(3)}',
      );
    } on PlatformException catch (error) {
      debugPrint('[LexPDF][WinPDF] ${error.code}: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(child: SizedBox.expand());
  }
}
