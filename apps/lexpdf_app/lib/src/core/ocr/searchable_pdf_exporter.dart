import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart' as cos;
import 'package:pdf_document/pdf_document.dart' as edit;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../storage/local_ocr_store.dart';
import 'local_pdf_byte_source.dart';

class SearchablePdfExportSummary {
  const SearchablePdfExportSummary({
    required this.file,
    required this.pageCount,
    required this.injectedPages,
    required this.injectedSpans,
    required this.alreadySearchablePages,
    required this.missingOcrPages,
    required this.appendedBytes,
  });

  final File file;
  final int pageCount;
  final int injectedPages;
  final int injectedSpans;
  final int alreadySearchablePages;
  final int missingOcrPages;
  final int appendedBytes;
}

class SearchablePdfExporter {
  const SearchablePdfExporter({required this.ocrStore});

  final LocalOcrStore ocrStore;

  /// Creates a searchable PDF without rasterizing or rebuilding the source.
  ///
  /// The original PDF bytes are streamed to a temporary output file and a
  /// compact incremental revision containing only invisible OCR text is
  /// appended. Vector text/images, forms, annotations, compression and page
  /// content remain byte-for-byte unchanged in the original revision. This is
  /// the preferred path for 2,000–5,000+ page documents.
  Future<SearchablePdfExportSummary> exportToFile({
    required String documentId,
    required String sourcePath,
    required String outputPath,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('PDF de origem não existe: $sourcePath');
    }
    if (_samePath(sourcePath, outputPath)) {
      throw ArgumentError('A exportação pesquisável deve usar um arquivo de destino diferente do original.');
    }

    final source = LocalPdfByteSource(sourcePath);
    final destination = File(outputPath);
    await destination.parent.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final partial = File('$outputPath.lexpdf-partial-$token');
    final backup = File('$outputPath.lexpdf-backup-$token');

    var replacedExisting = false;
    try {
      final document = await edit.PdfDocument.openSource(source);
      final editor = edit.PdfEditor(document);
      final total = document.pageCount;
      var injectedPages = 0;
      var injectedSpans = 0;
      var alreadySearchablePages = 0;
      var missingOcrPages = 0;

      for (var index = 0; index < total; index++) {
        if (isCancelled?.call() == true) {
          throw StateError('Exportação cancelada.');
        }

        final result = await ocrStore.getPage(documentId, index + 1);
        if (result == null || result.text.trim().isEmpty) {
          missingOcrPages++;
          onProgress?.call(index + 1, total);
          await _yieldIfNeeded(index + 1);
          continue;
        }

        // Pages processed from embedded text already contain searchable vector
        // text in the source PDF; injecting it again only bloats the file.
        if (result.engine == 'embedded-text') {
          alreadySearchablePages++;
          onProgress?.call(index + 1, total);
          await _yieldIfNeeded(index + 1);
          continue;
        }

        final page = document.page(index);
        final spans = _spansForResult(result, page);
        if (spans.isEmpty) {
          missingOcrPages++;
        } else {
          final count = editor.injectTextLayer(index, spans);
          if (count > 0) injectedPages++;
          injectedSpans += count;
        }
        onProgress?.call(index + 1, total);
        await _yieldIfNeeded(index + 1);
      }

      if (isCancelled?.call() == true) {
        throw StateError('Exportação cancelada.');
      }

      // saveTail returns only the incremental revision. It never serializes the
      // original multi-gigabyte document into a Dart Uint8List.
      final tail = editor.saveTail();

      final sink = partial.openWrite();
      try {
        await sourceFile.openRead().pipe(sink);
      } catch (_) {
        await sink.close();
        rethrow;
      }
      final append = partial.openWrite(mode: FileMode.append);
      try {
        append.add(tail);
      } finally {
        await append.close();
      }

      // Validate the completed incremental PDF before replacing an existing
      // destination. pdfrx opens from disk, so validation does not require a
      // second full-file heap copy.
      final verified = await pdfrx.PdfDocument.openFile(partial.path);
      try {
        if (verified.pages.length != total) {
          throw StateError(
            'PDF pesquisável inválido: esperado $total páginas, encontrado ${verified.pages.length}.',
          );
        }
      } finally {
        await verified.dispose();
      }

      if (await destination.exists()) {
        if (await backup.exists()) await backup.delete();
        await destination.rename(backup.path);
        replacedExisting = true;
      }
      try {
        await partial.rename(destination.path);
      } catch (_) {
        if (replacedExisting && await backup.exists()) {
          await backup.rename(destination.path);
          replacedExisting = false;
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
      replacedExisting = false;

      return SearchablePdfExportSummary(
        file: destination,
        pageCount: total,
        injectedPages: injectedPages,
        injectedSpans: injectedSpans,
        alreadySearchablePages: alreadySearchablePages,
        missingOcrPages: missingOcrPages,
        appendedBytes: tail.length,
      );
    } finally {
      await source.close();
      if (await partial.exists()) await partial.delete();
      if (replacedExisting && await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      } else if (await backup.exists()) {
        await backup.delete();
      }
    }
  }

  /// Compatibility API for legacy callers. New UI flows must use
  /// [exportToFile], because this method necessarily materializes the final
  /// result in memory before returning it.
  Future<Uint8List> export({
    required String documentId,
    required String sourcePath,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final temp = await Directory.systemTemp.createTemp('lexpdf-searchable-legacy-');
    try {
      final target = File('${temp.path}${Platform.pathSeparator}searchable.pdf');
      await exportToFile(
        documentId: documentId,
        sourcePath: sourcePath,
        outputPath: target.path,
        isCancelled: isCancelled,
        onProgress: onProgress,
      );
      return target.readAsBytes();
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  List<edit.PdfOcrSpan> _spansForResult(
    OcrPageResult result,
    edit.PdfPage page,
  ) {
    if (result.lines.isNotEmpty) {
      return [
        for (final line in result.lines)
          if (line.text.trim().isNotEmpty)
            edit.PdfOcrSpan(
              text: line.text.trim(),
              bounds: _normalizedRasterRectToUserSpace(
                page,
                x: line.x,
                y: line.y,
                width: line.width,
                height: line.height,
              ),
            ),
      ];
    }

    // Desktop engines can currently return plain text without geometry. Keep
    // it searchable without changing the visible page by distributing logical
    // lines vertically through the crop box. Geometry-aware OCR paths use the
    // precise branch above.
    final logicalLines = result.text
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (logicalLines.isEmpty) return const <edit.PdfOcrSpan>[];
    final box = page.cropBox;
    final lineHeight = box.height / logicalLines.length;
    return [
      for (var index = 0; index < logicalLines.length; index++)
        edit.PdfOcrSpan(
          text: logicalLines[index],
          bounds: edit.PdfRect(
            box.left,
            box.top - (index + 1) * lineHeight,
            box.right,
            box.top - index * lineHeight,
          ),
        ),
    ];
  }

  edit.PdfRect _normalizedRasterRectToUserSpace(
    edit.PdfPage page, {
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    final box = page.cropBox;
    final quarterTurn = page.rotation == 90 || page.rotation == 270;
    final displayWidth = quarterTurn ? box.height : box.width;
    final displayHeight = quarterTurn ? box.width : box.height;
    final left = x.clamp(0.0, 1.0) * displayWidth;
    final top = y.clamp(0.0, 1.0) * displayHeight;
    final right = (x + width).clamp(0.0, 1.0) * displayWidth;
    final bottom = (y + height).clamp(0.0, 1.0) * displayHeight;

    var userToDisplay = cos.PdfMatrix.translation(-box.left, -box.bottom)
        .concat(const cos.PdfMatrix(1, 0, 0, -1, 0, 0))
        .concat(cos.PdfMatrix.translation(0, box.height));
    switch (page.rotation) {
      case 90:
        userToDisplay = userToDisplay
            .concat(_rotation(math.pi / 2))
            .concat(cos.PdfMatrix.translation(displayWidth, 0));
      case 180:
        userToDisplay = userToDisplay
            .concat(_rotation(math.pi))
            .concat(cos.PdfMatrix.translation(displayWidth, displayHeight));
      case 270:
        userToDisplay = userToDisplay
            .concat(_rotation(-math.pi / 2))
            .concat(cos.PdfMatrix.translation(0, displayHeight));
    }
    final inverse = userToDisplay.inverted();
    if (inverse == null) return box;

    final points = <(double, double)>[
      inverse.apply(left, top),
      inverse.apply(right, top),
      inverse.apply(right, bottom),
      inverse.apply(left, bottom),
    ];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final (px, py) in points) {
      minX = math.min(minX, px);
      minY = math.min(minY, py);
      maxX = math.max(maxX, px);
      maxY = math.max(maxY, py);
    }
    return edit.PdfRect(minX, minY, maxX, maxY);
  }

  cos.PdfMatrix _rotation(double theta) {
    final c = math.cos(theta);
    final s = math.sin(theta);
    return cos.PdfMatrix(c, s, -s, c, 0, 0);
  }

  Future<void> _yieldIfNeeded(int pageNumber) async {
    if (pageNumber % 16 == 0) await Future<void>.delayed(Duration.zero);
  }

  bool _samePath(String a, String b) {
    String normalize(String value) {
      final absolute = File(value).absolute.path;
      return Platform.isWindows ? absolute.toLowerCase() : absolute;
    }
    return normalize(a) == normalize(b);
  }
}
