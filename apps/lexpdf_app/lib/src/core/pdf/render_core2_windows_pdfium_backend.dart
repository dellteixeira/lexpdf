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

class RenderCore2TextureFrameInfo {
  const RenderCore2TextureFrameInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.generation,
  });

  final int textureId;
  final int width;
  final int height;
  final int generation;
}

/// Minimal Windows bridge for the Render Core 2 PDFium prototype.
///
/// Phase 4 established the callable native boundary. Phase 5 added page metrics
/// and exact physical-pixel raster requests. Phase 6 adds a native Flutter
/// Texture path so page-sized pixels can stay outside Dart/ui.Image.
class RenderCore2WindowsPdfiumBackend implements LexPdfRenderSurface {
  RenderCore2WindowsPdfiumBackend({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'lexpdf/render_core2_pdfium';
  final MethodChannel _channel;

  String? _openedDocumentPath;
  int? _textureId;

  @override
  String get backendName => 'windows-pdfium-native-prototype';

  @override
  bool get isAvailable => Platform.isWindows;

  int? get textureId => _textureId;

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

  Future<int> createTexture() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Render Core 2 PDFium backend is Windows-only.');
    }
    final id = await _channel.invokeMethod<int>('createTexture');
    if (id == null || id < 0) {
      throw StateError('Native PDFium backend failed to register a texture.');
    }
    _textureId = id;
    return id;
  }

  Future<RenderCore2TextureFrameInfo> renderPageToTexture(
    LexPdfRenderRequest request,
  ) async {
    _validateRenderRequest(request);
    _textureId ??= await createTexture();

    final result = await _channel.invokeMapMethod<String, Object?>(
      'renderPageToTexture',
      _renderArguments(request),
    );
    if (result == null) {
      throw StateError('Native PDFium texture renderer returned no payload.');
    }

    final textureId = result['textureId'];
    final width = result['width'];
    final height = result['height'];
    final generation = result['generation'];
    if (textureId is! int ||
        width is! int ||
        height is! int ||
        generation is! int ||
        textureId < 0) {
      throw StateError('Native PDFium texture renderer returned invalid metadata.');
    }
    if (width != request.pixelWidth || height != request.pixelHeight) {
      throw StateError(
        'Native texture renderer did not honor physical pixel dimensions.',
      );
    }
    if (_textureId != textureId) {
      throw StateError('Native texture ID changed unexpectedly during rendering.');
    }

    return RenderCore2TextureFrameInfo(
      textureId: textureId,
      width: width,
      height: height,
      generation: generation,
    );
  }

  Future<void> disposeTexture() async {
    if (!Platform.isWindows) return;
    if (_textureId != null) {
      await _channel.invokeMethod<void>('disposeTexture');
      _textureId = null;
    }
  }

  @override
  Future<LexPdfRenderFrame> renderPage(LexPdfRenderRequest request) async {
    _validateRenderRequest(request);

    final result = await _channel.invokeMapMethod<String, Object?>(
      'renderPage',
      _renderArguments(request),
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

  void _validateRenderRequest(LexPdfRenderRequest request) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Render Core 2 PDFium backend is Windows-only.');
    }
    if (_openedDocumentPath != request.documentPath) {
      throw StateError('Requested document is not open in the native backend.');
    }
    if (request.pixelWidth <= 0 || request.pixelHeight <= 0) {
      throw ArgumentError('Physical pixel dimensions must be positive.');
    }
  }

  Map<String, Object?> _renderArguments(LexPdfRenderRequest request) =>
      <String, Object?>{
        'documentPath': request.documentPath,
        'pageNumber': request.pageNumber,
        'pixelWidth': request.pixelWidth,
        'pixelHeight': request.pixelHeight,
        'devicePixelRatio': request.devicePixelRatio,
        'viewerZoom': request.viewerZoom,
        'generation': request.generation,
      };

  @override
  Future<void> close() async {
    if (Platform.isWindows && _openedDocumentPath != null) {
      await _channel.invokeMethod<void>('closeDocument');
    }
    _openedDocumentPath = null;
  }
}
