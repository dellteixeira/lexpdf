import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

class PdfPageVisionRasterizer {
  const PdfPageVisionRasterizer();

  static const int maxPixels = 2400000;

  Future<Uint8List> rasterize({
    required String filePath,
    required int pageNumber,
  }) async {
    final document = await PdfDocument.openFile(filePath);
    try {
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        throw RangeError('Página fora do intervalo do PDF.');
      }
      final page = document.pages[pageNumber - 1];
      final aspect = page.width / page.height;
      final height = math.sqrt(maxPixels / aspect).round().clamp(1, 2600);
      final width = (height * aspect).round().clamp(1, 2600);
      final rendered = await page.render(
        width: width,
        height: height,
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) {
        throw StateError('Não foi possível rasterizar a página.');
      }
      try {
        return Uint8List.fromList(
          img.encodeJpg(rendered.createImageNF(), quality: 86),
        );
      } finally {
        rendered.dispose();
      }
    } finally {
      await document.dispose();
    }
  }
}
