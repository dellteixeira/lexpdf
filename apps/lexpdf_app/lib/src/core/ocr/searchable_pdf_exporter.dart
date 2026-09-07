import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as gen;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../pdf/huge_pdf_policy.dart';
import '../storage/local_ocr_store.dart';

class SearchablePdfExporter {
  const SearchablePdfExporter({required this.ocrStore});

  final LocalOcrStore ocrStore;

  /// Builds searchable PDFs in bounded chunks so rendered page images are not
  /// retained for the full 2,000–5,000+ page document.
  Future<Uint8List> export({
    required String documentId,
    required String sourcePath,
    double renderScale = 1.5,
    int pagesPerChunk = 16,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (pagesPerChunk < 1 || pagesPerChunk > 64) {
      throw ArgumentError.value(pagesPerChunk, 'pagesPerChunk', 'Must be 1..64.');
    }
    final source = await PdfDocument.openFile(sourcePath);
    final temp = await Directory.systemTemp.createTemp('lexpdf-searchable-export-');
    final chunkPaths = <String>[];
    try {
      final total = source.pages.length;
      for (var start = 0; start < total; start += pagesPerChunk) {
        if (isCancelled?.call() == true) {
          throw StateError('Exportação cancelada.');
        }
        final end = math.min(total, start + pagesPerChunk);
        final output = pw.Document(compress: true);
        for (var index = start; index < end; index++) {
          if (isCancelled?.call() == true) {
            throw StateError('Exportação cancelada.');
          }
          final page = source.pages[index];
          final preferredScale = math.min(renderScale, HugePdfPolicy.ocrPreferredScale);
          final size = HugePdfPolicy.boundedRenderSize(
            pageWidth: page.width,
            pageHeight: page.height,
            preferredScale: preferredScale,
          );
          final render = await page.render(
            width: size.width,
            height: size.height,
            backgroundColor: 0xFFFFFFFF,
            annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
          );
          if (render == null) {
            throw StateError('Não foi possível renderizar a página ${page.pageNumber}.');
          }

          late final Uint8List jpegBytes;
          try {
            jpegBytes = Uint8List.fromList(
              img.encodeJpg(render.createImageNF(), quality: 88),
            );
          } finally {
            render.dispose();
          }

          final base = pw.MemoryImage(jpegBytes);
          final ocr = await ocrStore.getPage(documentId, page.pageNumber);
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
          onProgress?.call(index + 1, total);
        }
        final chunk = File(
          '${temp.path}${Platform.pathSeparator}chunk_${(start ~/ pagesPerChunk).toString().padLeft(5, '0')}.pdf',
        );
        await chunk.writeAsBytes(await output.save(), flush: true);
        chunkPaths.add(chunk.path);
      }

      final chunkDocs = <PdfDocument>[];
      final merged = await PdfDocument.createNew(sourceName: 'lexpdf-searchable.pdf');
      try {
        for (final path in chunkPaths) {
          chunkDocs.add(await PdfDocument.openFile(path));
        }
        merged.pages = [for (final doc in chunkDocs) ...doc.pages];
        return await merged.encodePdf();
      } finally {
        await merged.dispose();
        for (final doc in chunkDocs) {
          await doc.dispose();
        }
      }
    } finally {
      await source.dispose();
      if (await temp.exists()) await temp.delete(recursive: true);
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
