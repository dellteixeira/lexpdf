import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as gen;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../storage/local_ocr_store.dart';

class SearchablePdfExporter {
  const SearchablePdfExporter({required this.ocrStore});

  final LocalOcrStore ocrStore;

  Future<Uint8List> export({
    required String documentId,
    required String sourcePath,
    double renderScale = 1.5,
  }) async {
    final source = await PdfDocument.openFile(sourcePath);
    final results = await ocrStore.listForDocument(documentId);
    final byPage = {for (final result in results) result.pageNumber: result};
    final output = pw.Document();

    try {
      for (final page in source.pages) {
        final render = await page.render(
          width: math.max(1, (page.width * renderScale).round()),
          height: math.max(1, (page.height * renderScale).round()),
          backgroundColor: 0xFFFFFFFF,
          annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
        );
        if (render == null) {
          throw StateError('Não foi possível renderizar a página ${page.pageNumber}.');
        }

        late final Uint8List pngBytes;
        try {
          pngBytes = Uint8List.fromList(img.encodePng(render.createImageNF()));
        } finally {
          render.dispose();
        }

        final base = pw.MemoryImage(pngBytes);
        final ocr = byPage[page.pageNumber];
        output.addPage(
          pw.Page(
            pageFormat: gen.PdfPageFormat(page.width, page.height, marginAll: 0),
            build: (_) => pw.Stack(
              children: [
                pw.Image(
                  base,
                  width: page.width,
                  height: page.height,
                  fit: pw.BoxFit.fill,
                ),
                if (ocr != null) ..._buildTextLayer(ocr, page.width, page.height),
              ],
            ),
          ),
        );
      }
      return await output.save();
    } finally {
      await source.dispose();
    }
  }

  List<pw.Widget> _buildTextLayer(
    OcrPageResult result,
    double pageWidth,
    double pageHeight,
  ) {
    if (result.text.trim().isEmpty) return const [];
    const invisible = gen.PdfColor(0, 0, 0, 0.001);

    if (result.lines.isNotEmpty) {
      return [
        for (final line in result.lines)
          if (line.text.trim().isNotEmpty)
            pw.Positioned(
              left: line.x * pageWidth,
              top: line.y * pageHeight,
              child: pw.SizedBox(
                width: math.max(1, line.width * pageWidth),
                height: math.max(1, line.height * pageHeight),
                child: pw.FittedBox(
                  fit: pw.BoxFit.contain,
                  alignment: pw.Alignment.topLeft,
                  child: pw.Text(
                    line.text,
                    maxLines: 1,
                    style: pw.TextStyle(
                      color: invisible,
                      fontSize: math.max(2, line.height * pageHeight),
                    ),
                  ),
                ),
              ),
            ),
      ];
    }

    return [
      pw.Positioned(
        left: 2,
        top: 2,
        child: pw.SizedBox(
          width: math.max(1, pageWidth - 4),
          child: pw.Text(
            result.text,
            style: const pw.TextStyle(color: invisible, fontSize: 2),
          ),
        ),
      ),
    ];
  }
}
