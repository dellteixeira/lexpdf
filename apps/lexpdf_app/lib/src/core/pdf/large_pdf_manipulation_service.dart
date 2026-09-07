import 'dart:io';

import 'package:pdf_document/pdf_document.dart' as edit;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../ocr/local_pdf_byte_source.dart';

/// Disk-oriented manipulation paths for very large PDFs.
///
/// These operations avoid rebuilding every page in memory. The original PDF
/// revision is streamed to disk and only a compact incremental revision is
/// appended for targeted edits.
class LargePdfManipulationService {
  const LargePdfManipulationService();

  Future<File> insertImageOnPageToFile({
    required String sourcePath,
    required String imagePath,
    required int pageNumber,
    required String outputPath,
    double leftFraction = 0.10,
    double topFraction = 0.10,
    double widthFraction = 0.35,
  }) async {
    if (leftFraction < 0 ||
        leftFraction > 1 ||
        topFraction < 0 ||
        topFraction > 1 ||
        widthFraction <= 0 ||
        widthFraction > 1) {
      throw ArgumentError('Image placement must use normalized page fractions.');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('PDF de origem não existe: $sourcePath');
    }
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw StateError('Imagem não existe: $imagePath');
    }
    if (_samePath(sourcePath, outputPath)) {
      throw ArgumentError('A edição deve ser salva em um arquivo diferente do original.');
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
      if (pageNumber < 1 || pageNumber > document.pageCount) {
        throw RangeError.range(pageNumber, 1, document.pageCount, 'pageNumber');
      }

      final image = edit.PdfEmbeddableImage.decode(await imageFile.readAsBytes());
      final page = document.page(pageNumber - 1);
      final box = page.cropBox;
      final targetWidth = box.width * widthFraction;
      final targetHeight = targetWidth * image.height / image.width;
      final x = box.left + box.width * leftFraction;
      final top = box.top - box.height * topFraction;
      final y = top - targetHeight;

      final editor = edit.PdfEditor(document);
      editor.stampPage(pageNumber - 1, (stamp) {
        stamp.image(
          image,
          x: x,
          y: y,
          width: targetWidth,
          height: targetHeight,
        );
      });
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

      final verified = await pdfrx.PdfDocument.openFile(partial.path);
      try {
        if (verified.pages.length != document.pageCount) {
          throw StateError(
            'PDF editado inválido: esperado ${document.pageCount} páginas, encontrado ${verified.pages.length}.',
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
      return destination;
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

  bool _samePath(String a, String b) {
    String normalize(String value) {
      final absolute = File(value).absolute.path;
      return Platform.isWindows ? absolute.toLowerCase() : absolute;
    }
    return normalize(a) == normalize(b);
  }
}
