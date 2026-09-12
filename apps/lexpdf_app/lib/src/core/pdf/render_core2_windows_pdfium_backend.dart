import 'dart:io';

import 'package:flutter/services.dart';

import 'lexpdf_render_surface.dart';

class RenderCore2PdfPageInfo {
  const RenderCore2PdfPageInfo({
    required this.pageNumber,
    required this.pageCount,
    required this.widthPoints,
    required this.heightPoints,
  });

  final int pageNumber;
  final int pageCount;
  final double widthPoints;
  final double heightPoints;
}

/// Minimal Windows bridge for the Render Core 2 PDFium prototype.
///
/// Phase 4 established the callable native boundary. Phase 5 adds page metrics
/// so a standalone diagnostic view can request one page at exact physical-pixel
/// dimensions without changing the production workspace renderer.
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

  Future<RenderCore2PdfPageInfo> getPageInfo(int pageNumber) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Render Core 2 PDFium backend is Windows-only.');
    }
    if (_openedDocumentPath == null) {
      throw StateError('No document is open in the native backend.');
    }
    if (pageNumber <= 0) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'Must be positive.');
    }

    final result = await _channel.invokeMapMethod<String, Object?>(
      'getPageInfo',
      <String, Object?>{'pageNumber': pageNumber},
    );
    if (result == null) {
      throw StateError('Native PDFium backend returned no page metadata.');
    }

    final returnedPage = result['pageNumber'];
    final pageCount = result['pageCount'];
    final width = result['widthPoints'];
    final height = result['heightPoints'];
    if (returnedPage is! int ||
        pageCount is! int ||
        width is! double ||
        height is! double ||
        returnedPage != pageNumber ||
        pageCount <= 0 ||
        width <= 0 ||
        height <= 0) {
      throw StateError('Native PDFium backend returned invalid page metadata.');
    }

    return RenderCore2PdfPageInfo(
      pageNumber: returnedPage,
      pageCount: pageCount,
      widthPoints: width,
      heightPoints: height,
    );
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
