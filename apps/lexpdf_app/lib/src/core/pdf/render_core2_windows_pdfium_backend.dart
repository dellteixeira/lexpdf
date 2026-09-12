import 'dart:io';

import 'package:flutter/services.dart';

import 'lexpdf_render_surface.dart';

/// Minimal Windows bridge for the Render Core 2 PDFium prototype.
///
/// Phase 4 establishes the callable native boundary only. Production workspace
/// rendering is intentionally not switched to this backend until the native
/// implementation and physical-pixel output are validated.
class RenderCore2WindowsPdfiumBackend implements LexPdfRenderSurface {
  RenderCore2WindowsPdfiumBackend({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'lexpdf/render_core2_pdfium';
  final MethodChannel _channel;

  String? _openedDocumentPath;

  @override
  String get backendName => 'windows-pdfium-native-prototype';

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  Future<void> open(String documentPath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Render Core 2 PDFium backend is Windows-only.');
    }
    final opened = await _channel.invokeMethod<bool>(
      'openDocument',
      <String, Object?>{'documentPath': documentPath},
    );
    if (opened != true) {
      throw StateError('Native PDFium backend failed to open the document.');
    }
    _openedDocumentPath = documentPath;
  }

  @override
  Future<LexPdfRenderFrame> renderPage(LexPdfRenderRequest request) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Render Core 2 PDFium backend is Windows-only.');
    }
    if (_openedDocumentPath != request.documentPath) {
      throw StateError('Requested document is not open in the native backend.');
    }
    if (request.pixelWidth <= 0 || request.pixelHeight <= 0) {
      throw ArgumentError('Physical pixel dimensions must be positive.');
    }

    final result = await _channel.invokeMapMethod<String, Object?>(
      'renderPage',
      <String, Object?>{
        'documentPath': request.documentPath,
        'pageNumber': request.pageNumber,
        'pixelWidth': request.pixelWidth,
        'pixelHeight': request.pixelHeight,
        'devicePixelRatio': request.devicePixelRatio,
        'viewerZoom': request.viewerZoom,
        'generation': request.generation,
      },
    );

    if (result == null) {
      throw StateError('Native PDFium renderer returned no payload.');
    }

    final pixels = result['bgra8888'];
    final width = result['width'];
    final height = result['height'];
    final rowBytes = result['rowBytes'];
    final generation = result['generation'];

    if (pixels is! Uint8List ||
        width is! int ||
        height is! int ||
        rowBytes is! int ||
        generation is! int) {
      throw StateError('Native PDFium renderer returned an invalid payload.');
    }
    if (width != request.pixelWidth || height != request.pixelHeight) {
      throw StateError('Native renderer did not honor physical pixel dimensions.');
    }
    if (rowBytes < width * 4 || pixels.lengthInBytes < rowBytes * height) {
      throw StateError('Native renderer returned an invalid BGRA8888 buffer.');
    }

    return LexPdfRenderFrame(
      width: width,
      height: height,
      rowBytes: rowBytes,
      bgra8888: pixels,
      generation: generation,
    );
  }

  @override
  Future<void> close() async {
    if (Platform.isWindows && _openedDocumentPath != null) {
      await _channel.invokeMethod<void>('closeDocument');
    }
    _openedDocumentPath = null;
  }
}
