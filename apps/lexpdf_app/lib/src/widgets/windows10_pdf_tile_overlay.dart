import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/pdf/render_core2_scale_model.dart';

/// Returns the Windows build number from [Platform.operatingSystemVersion].
///
/// Typical values contain `10.0.19045` (Windows 10) or `10.0.22631`
/// (Windows 11). Keeping the parser independent makes the platform gate easy
/// to regression-test without requiring a Windows host.
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

/// Windows 10 uses a manual tiled PDF page renderer in LexPDF.
///
/// The normal pdfrx viewer remains responsible for page layout, navigation,
/// links and text selection. Only the visual PDF page surface is replaced.
/// This deliberately bypasses pdfrx's large-page bitmap composition path,
/// which is the path that has shown corruption on physical Windows 10 hosts.
bool isWindows10ManualTileRenderingEnabled() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;

  final override = Platform.environment['LEXPDF_WINDOWS10_TILED_RENDERING'];
  if (override == '1') return true;
  if (override == '0') return false;

  final build = parseWindowsBuildNumber(Platform.operatingSystemVersion);
  return build != null && build >= 10240 && build < 22000;
}

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
  static const int _tilePixels = 768;
  static const Duration _settleDelay = Duration(milliseconds: 45);

  final Map<_TileKey, _TileEntry> _tiles = <_TileKey, _TileEntry>{};
  Timer? _settleTimer;
  int _generation = 0;
  int? _activeScaleKey;

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
    if (oldWidget.page != widget.page || oldWidget.pageRect != widget.pageRect) {
      _disposeTiles();
      _activeScaleKey = null;
    }
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _generation++;
    _settleTimer?.cancel();
    widget.controller.removeListener(_scheduleRefresh);
    _disposeTiles();
    super.dispose();
  }

  void _scheduleRefresh() {
    if (!mounted || !widget.controller.isReady) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () => unawaited(_refreshVisibleTiles()));
  }

  Future<void> _refreshVisibleTiles() async {
    if (!mounted || !widget.controller.isReady) return;

    final visible = widget.controller.visibleRect;
    final pageRect = widget.pageRect;
    if (!visible.overlaps(pageRect)) return;

    final intersection = visible.intersect(pageRect);
    if (intersection.width <= 0 || intersection.height <= 0) return;

    final dpr = View.of(context).devicePixelRatio;
    final scaleModel = RenderCore2ScaleModel.fromViewerRect(
      pageWidthPoints: widget.page.width,
      pageHeightPoints: widget.page.height,
      pageRectWidthLogical: pageRect.width,
      pageRectHeightLogical: pageRect.height,
      currentZoom: widget.controller.currentZoom,
      devicePixelRatio: dpr,
    );

    // pageRect is already in viewer coordinates and already reflects viewer
    // layout/zoom. Convert viewer logical pixels to physical pixels with DPR
    // exactly once. Multiplying currentZoom here again is a coordinate-space
    // error: below 100% it undersamples and above 100% it over-renders.
    final scale = dpr;
    final scaleKey = (scale * 1000).round();

    if (_activeScaleKey != scaleKey) {
      _generation++;
      _activeScaleKey = scaleKey;
      _disposeTiles();
      if (mounted) setState(() {});
    }

    final generation = ++_generation;
    final fullWidth = scaleModel.targetPixelWidth;
    final fullHeight = scaleModel.targetPixelHeight;

    final local = intersection.shift(-pageRect.topLeft);
    final leftPixel = (local.left * scale).floor().clamp(0, fullWidth - 1);
    final topPixel = (local.top * scale).floor().clamp(0, fullHeight - 1);
    final rightPixel = (local.right * scale).ceil().clamp(1, fullWidth);
    final bottomPixel = (local.bottom * scale).ceil().clamp(1, fullHeight);

    final firstX = math.max(0, leftPixel ~/ _tilePixels - 1);
    final firstY = math.max(0, topPixel ~/ _tilePixels - 1);
    final lastX = math.min(
      (fullWidth - 1) ~/ _tilePixels,
      (rightPixel - 1) ~/ _tilePixels + 1,
    );
    final lastY = math.min(
      (fullHeight - 1) ~/ _tilePixels,
      (bottomPixel - 1) ~/ _tilePixels + 1,
    );

    final wanted = <_TileKey>[];
    for (var tileY = firstY; tileY <= lastY; tileY++) {
      for (var tileX = firstX; tileX <= lastX; tileX++) {
        wanted.add(
          _TileKey(scaleKey: scaleKey, tileX: tileX, tileY: tileY),
        );
      }
    }

    // Render from the center outward so the area under the pointer/viewport
    // becomes sharp first.
    final centerX = ((leftPixel + rightPixel) / 2) / _tilePixels;
    final centerY = ((topPixel + bottomPixel) / 2) / _tilePixels;
    wanted.sort((a, b) {
      final da = math.pow(a.tileX - centerX, 2) +
          math.pow(a.tileY - centerY, 2);
      final db = math.pow(b.tileX - centerX, 2) +
          math.pow(b.tileY - centerY, 2);
      return da.compareTo(db);
    });

    final wantedSet = wanted.toSet();
    final staleKeys = _tiles.keys.where((key) => !wantedSet.contains(key)).toList();
    for (final key in staleKeys) {
      _tiles.remove(key)?.image.dispose();
    }
    if (staleKeys.isNotEmpty && mounted) setState(() {});

    try {
      await widget.page.ensureLoaded();
    } catch (_) {
      return;
    }

    for (final key in wanted) {
      if (!mounted || generation != _generation) return;
      if (_tiles.containsKey(key)) continue;

      final x = key.tileX * _tilePixels;
      final y = key.tileY * _tilePixels;
      final width = math.min(_tilePixels, fullWidth - x);
      final height = math.min(_tilePixels, fullHeight - y);
      if (width <= 0 || height <= 0) continue;

      PdfImage? rendered;
      try {
        rendered = await widget.page.render(
          x: x,
          y: y,
          width: width,
          height: height,
          fullWidth: fullWidth.toDouble(),
          fullHeight: fullHeight.toDouble(),
          backgroundColor: 0xFFFFFFFF,
          flags: PdfPageRenderFlags.none,
        );
        if (rendered == null || !mounted || generation != _generation) {
          rendered?.dispose();
          return;
        }

        final image = await _decodeBgra(rendered);
        rendered.dispose();
        rendered = null;
        if (!mounted || generation != _generation) {
          image.dispose();
          return;
        }

        _tiles[key] = _TileEntry(
          image: image,
          x: x,
          y: y,
          width: width,
          height: height,
          scale: scale,
        );
        setState(() {});
      } catch (_) {
        rendered?.dispose();
        // Keep the page usable even if one tile fails. Another viewer update
        // will retry the missing tile.
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

  void _disposeTiles() {
    for (final tile in _tiles.values) {
      tile.image.dispose();
    }
    _tiles.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scaleKey = _activeScaleKey;
    return IgnorePointer(
      child: ColoredBox(
        // Opaque white intentionally hides pdfrx's underlying large page
        // bitmap on Windows 10. The tile layer remains an intermediate
        // diagnostic path while Render Core 2 moves toward a native surface.
        color: Colors.white,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final entry in _tiles.entries)
              if (entry.key.scaleKey == scaleKey)
                Positioned(
                  left: entry.value.x / entry.value.scale,
                  top: entry.value.y / entry.value.scale,
                  width: entry.value.width / entry.value.scale,
                  height: entry.value.height / entry.value.scale,
                  child: RawImage(
                    image: entry.value.image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.low,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TileKey {
  const _TileKey({
    required this.scaleKey,
    required this.tileX,
    required this.tileY,
  });

  final int scaleKey;
  final int tileX;
  final int tileY;

  @override
  bool operator ==(Object other) =>
      other is _TileKey &&
      other.scaleKey == scaleKey &&
      other.tileX == tileX &&
      other.tileY == tileY;

  @override
  int get hashCode => Object.hash(scaleKey, tileX, tileY);
}

class _TileEntry {
  const _TileEntry({
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.scale,
  });

  final ui.Image image;
  final int x;
  final int y;
  final int width;
  final int height;
  final double scale;
}
