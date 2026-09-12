import 'dart:typed_data';

class LexPdfRenderRequest {
  const LexPdfRenderRequest({
    required this.documentPath,
    required this.pageNumber,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.devicePixelRatio,
    required this.viewerZoom,
    this.generation = 0,
  });

  final String documentPath;
  final int pageNumber;
  final int pixelWidth;
  final int pixelHeight;
  final double devicePixelRatio;
  final double viewerZoom;
  final int generation;
}

class LexPdfRenderFrame {
  const LexPdfRenderFrame({
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.bgra8888,
    required this.generation,
  });

  final int width;
  final int height;
  final int rowBytes;
  final Uint8List bgra8888;
  final int generation;
}

abstract interface class LexPdfRenderSurface {
  String get backendName;

  bool get isAvailable;

  Future<void> open(String documentPath);

  Future<LexPdfRenderFrame> renderPage(LexPdfRenderRequest request);

  Future<void> close();
}
