import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart' as edit;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../ocr/local_pdf_byte_source.dart';
import 'pdf_page_manipulation_service.dart';

/// Disk-oriented manipulation paths for very large PDFs.
///
/// The implementation keeps the original/vector PDF objects whenever possible
/// and commits edits as incremental revisions. Composition is performed in
/// small page batches, so the amount of imported PDF object data retained by
/// one editor session is bounded by [composeChunkPages] instead of total page
/// count. This is the preferred path for 2,000–5,000+ page documents.
class LargePdfManipulationService {
  const LargePdfManipulationService();

  static const int composeChunkPages = 32;

  Future<File> composeToFile(
    List<PdfPageSpec> specs, {
    required String outputPath,
    int chunkPages = composeChunkPages,
  }) async {
    if (specs.isEmpty) {
      throw ArgumentError('At least one PDF page is required.');
    }
    if (chunkPages < 1 || chunkPages > 128) {
      throw ArgumentError.value(chunkPages, 'chunkPages', 'Must be 1..128.');
    }

    final destination = File(outputPath);
    await destination.parent.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final partial = File('$outputPath.lexpdf-partial-$token');
    final backup = File('$outputPath.lexpdf-backup-$token');
    var replacedExisting = false;

    try {
      // A tiny bootstrap revision gives PdfEditor a destination document.
      // It is removed in the final incremental revision after all requested
      // pages have been imported.
      await partial.writeAsBytes(edit.PdfBlankDocument.create(), flush: true);

      for (var start = 0; start < specs.length; start += chunkPages) {
        final end = (start + chunkPages).clamp(0, specs.length);
        final chunk = specs.sublist(start, end);
        final destinationSource = LocalPdfByteSource(partial.path);
        final sourceHandles = <String, LocalPdfByteSource>{};
        final sourceDocuments = <String, edit.PdfDocument>{};
        Uint8List tail;
        try {
          final document = await edit.PdfDocument.openSource(destinationSource);
          final editor = edit.PdfEditor(document);

          for (final spec in chunk) {
            final source = sourceHandles[spec.sourcePath] ??=
                LocalPdfByteSource(spec.sourcePath);
            final sourceDocument = sourceDocuments[spec.sourcePath] ??=
                await edit.PdfDocument.openSource(source);
            if (spec.pageNumber < 1 || spec.pageNumber > sourceDocument.pageCount) {
              throw RangeError.range(
                spec.pageNumber,
                1,
                sourceDocument.pageCount,
                'pageNumber',
              );
            }

            final insertIndex = document.pageCount;
            editor.appendPagesFrom(
              sourceDocument,
              indices: [spec.pageNumber - 1],
            );
            final turns = spec.clockwiseQuarterTurns % 4;
            if (turns != 0) {
              editor.rotatePages([insertIndex], turns * 90);
            }
          }
          tail = editor.saveTail();
        } finally {
          await destinationSource.close();
          for (final source in sourceHandles.values) {
            await source.close();
          }
        }
        await _appendTail(partial, tail);
        await Future<void>.delayed(Duration.zero);
      }

      // Drop the bootstrap page without rewriting the imported pages.
      final finalSource = LocalPdfByteSource(partial.path);
      Uint8List finalTail;
      try {
        final document = await edit.PdfDocument.openSource(finalSource);
        final editor = edit.PdfEditor(document)..removePage(0);
        finalTail = editor.saveTail();
      } finally {
        await finalSource.close();
      }
      await _appendTail(partial, finalTail);

      await _validatePageCount(partial.path, specs.length);
      replacedExisting = await _replaceWithBackup(
        partial: partial,
        destination: destination,
        backup: backup,
      );
      // _replaceWithBackup returns false after a successful commit; the value
      // is only used by the recovery block if an exception interrupts it.
      return destination;
    } finally {
      if (await partial.exists()) await partial.delete();
      if (replacedExisting && await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      } else if (await backup.exists()) {
        await backup.delete();
      }
    }
  }

  /// Combines PDFs without encoding the complete combined output into one
  /// Uint8List. The first PDF is streamed verbatim as the base revision; each
  /// later source is imported and appended as one incremental revision.
  Future<File> mergeToFile(
    List<String> sourcePaths, {
    required String outputPath,
  }) async {
    if (sourcePaths.isEmpty) {
      throw ArgumentError('At least one PDF is required.');
    }
    for (final path in sourcePaths) {
      if (!await File(path).exists()) {
        throw StateError('PDF de origem não existe: $path');
      }
    }
    if (sourcePaths.any((path) => _samePath(path, outputPath))) {
      throw ArgumentError('A combinação deve usar um arquivo de destino diferente das origens.');
    }

    final destination = File(outputPath);
    await destination.parent.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final partial = File('$outputPath.lexpdf-partial-$token');
    final backup = File('$outputPath.lexpdf-backup-$token');
    var replacedExisting = false;
    var expectedPages = 0;

    try {
      await File(sourcePaths.first).openRead().pipe(partial.openWrite());
      expectedPages = await _pageCount(sourcePaths.first);

      for (final incomingPath in sourcePaths.skip(1)) {
        final destinationSource = LocalPdfByteSource(partial.path);
        final incomingSource = LocalPdfByteSource(incomingPath);
        Uint8List tail;
        int incomingPages;
        try {
          final document = await edit.PdfDocument.openSource(destinationSource);
          final incoming = await edit.PdfDocument.openSource(incomingSource);
          incomingPages = incoming.pageCount;
          final editor = edit.PdfEditor(document)
            ..appendPagesFrom(incoming);
          tail = editor.saveTail();
        } finally {
          await destinationSource.close();
          await incomingSource.close();
        }
        await _appendTail(partial, tail);
        expectedPages += incomingPages;
        await Future<void>.delayed(Duration.zero);
      }

      await _validatePageCount(partial.path, expectedPages);
      replacedExisting = await _replaceWithBackup(
        partial: partial,
        destination: destination,
        backup: backup,
      );
      return destination;
    } finally {
      if (await partial.exists()) await partial.delete();
      if (replacedExisting && await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      } else if (await backup.exists()) {
        await backup.delete();
      }
    }
  }

  Future<File> addBlankPageToFile({
    required String sourcePath,
    required String outputPath,
    int? afterPageNumber,
    double? width,
    double? height,
  }) async {
    return _singleIncrementalEdit(
      sourcePath: sourcePath,
      outputPath: outputPath,
      editDocument: (document, editor) {
        final insertAt = (afterPageNumber ?? document.pageCount)
            .clamp(0, document.pageCount);
        editor.insertBlankPage(
          at: insertAt,
          width: width,
          height: height,
        );
      },
      expectedPageDelta: 1,
    );
  }

  /// Creates an image PDF one image at a time, staging one-page PDFs on disk
  /// and composing them through [composeToFile]. No list of decoded images or
  /// image-backed PdfDocuments is retained for the whole operation.
  Future<File> imagesToPdfToFile(
    List<String> imagePaths, {
    required String outputPath,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('At least one image is required.');
    }
    final temp = await Directory.systemTemp.createTemp('lexpdf-image-pages-');
    try {
      final specs = <PdfPageSpec>[];
      for (var index = 0; index < imagePaths.length; index++) {
        final imageFile = File(imagePaths[index]);
        if (!await imageFile.exists()) {
          throw StateError('Imagem não existe: ${imagePaths[index]}');
        }
        final sourceBytes = await imageFile.readAsBytes();
        final normalized = _normalizeImageBytes(sourceBytes, imagePaths[index]);
        final pageBytes = edit.PdfImageDocument.fromImageBytes(
          [normalized],
          pageSize: edit.PdfPageSize.a4,
          fit: edit.PdfImageFit.contain,
        );
        final pageFile = File(
          '${temp.path}${Platform.pathSeparator}image_${index.toString().padLeft(6, '0')}.pdf',
        );
        await pageFile.writeAsBytes(pageBytes, flush: true);
        specs.add(PdfPageSpec(sourcePath: pageFile.path, pageNumber: 1));
        await Future<void>.delayed(Duration.zero);
      }
      return composeToFile(specs, outputPath: outputPath);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

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
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw StateError('Imagem não existe: $imagePath');
    }
    final normalizedImage = _normalizeImageBytes(
      await imageFile.readAsBytes(),
      imagePath,
    );
    final image = edit.PdfEmbeddableImage.decode(normalizedImage);

    return _singleIncrementalEdit(
      sourcePath: sourcePath,
      outputPath: outputPath,
      editDocument: (document, editor) {
        if (pageNumber < 1 || pageNumber > document.pageCount) {
          throw RangeError.range(pageNumber, 1, document.pageCount, 'pageNumber');
        }
        final page = document.page(pageNumber - 1);
        final box = page.cropBox;
        final targetWidth = box.width * widthFraction;
        final targetHeight = targetWidth * image.height / image.width;
        final x = box.left + box.width * leftFraction;
        final top = box.top - box.height * topFraction;
        final y = top - targetHeight;
        editor.stampPage(pageNumber - 1, (stamp) {
          stamp.image(
            image,
            x: x,
            y: y,
            width: targetWidth,
            height: targetHeight,
          );
        });
      },
    );
  }

  Future<File> _singleIncrementalEdit({
    required String sourcePath,
    required String outputPath,
    required void Function(edit.PdfDocument document, edit.PdfEditor editor)
        editDocument,
    int expectedPageDelta = 0,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('PDF de origem não existe: $sourcePath');
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
    late int expectedPages;
    late Uint8List tail;

    try {
      final document = await edit.PdfDocument.openSource(source);
      expectedPages = document.pageCount + expectedPageDelta;
      final editor = edit.PdfEditor(document);
      editDocument(document, editor);
      tail = editor.saveTail();
      await source.close();

      await sourceFile.openRead().pipe(partial.openWrite());
      await _appendTail(partial, tail);
      await _validatePageCount(partial.path, expectedPages);

      replacedExisting = await _replaceWithBackup(
        partial: partial,
        destination: destination,
        backup: backup,
      );
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

  Uint8List _normalizeImageBytes(Uint8List bytes, String path) {
    try {
      edit.PdfEmbeddableImage.decode(bytes);
      return bytes;
    } catch (_) {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw FormatException('Unsupported image: $path');
      }
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
    }
  }

  Future<int> _pageCount(String path) async {
    final source = LocalPdfByteSource(path);
    try {
      final document = await edit.PdfDocument.openSource(source);
      return document.pageCount;
    } finally {
      await source.close();
    }
  }

  Future<void> _appendTail(File file, Uint8List tail) async {
    if (tail.isEmpty) return;
    final sink = file.openWrite(mode: FileMode.append);
    try {
      sink.add(tail);
    } finally {
      await sink.close();
    }
  }

  Future<void> _validatePageCount(String path, int expected) async {
    final verified = await pdfrx.PdfDocument.openFile(path);
    try {
      if (verified.pages.length != expected) {
        throw StateError(
          'PDF editado inválido: esperado $expected páginas, encontrado ${verified.pages.length}.',
        );
      }
    } finally {
      await verified.dispose();
    }
  }

  /// Returns true only while an old destination is parked in [backup]. A
  /// successful commit always returns false because the backup is deleted.
  Future<bool> _replaceWithBackup({
    required File partial,
    required File destination,
    required File backup,
  }) async {
    var replacedExisting = false;
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
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
    return false;
  }

  bool _samePath(String a, String b) {
    String normalize(String value) {
      final absolute = File(value).absolute.path;
      return Platform.isWindows ? absolute.toLowerCase() : absolute;
    }
    return normalize(a) == normalize(b);
  }
}
