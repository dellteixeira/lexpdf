import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

class PdfSafeWriteResult {
  const PdfSafeWriteResult({
    required this.outputPath,
    required this.pageCount,
    this.backupPath,
  });

  final String outputPath;
  final int pageCount;
  final String? backupPath;
}

class PdfDocumentToolService {
  const PdfDocumentToolService();

  Future<PdfSafeWriteResult> reorder({
    required String sourcePath,
    required List<int> pageOrder,
    required String outputPath,
  }) async {
    final source = await _open(sourcePath);
    try {
      _validatePages(pageOrder, source.pages.length, allowDuplicates: true);
      final output = await PdfDocument.createNew(sourceName: outputPath);
      try {
        output.pages = [for (final number in pageOrder) source.pages[number - 1]];
        return _encodeValidateAndWrite(output, outputPath);
      } finally {
        await output.dispose();
      }
    } finally {
      await source.dispose();
    }
  }

  Future<PdfSafeWriteResult> rotate({
    required String sourcePath,
    required Set<int> pages,
    required PdfPageRotation rotation,
    required String outputPath,
  }) async {
    final source = await _open(sourcePath);
    try {
      _validatePages(pages.toList(), source.pages.length);
      final output = await PdfDocument.createNew(sourceName: outputPath);
      try {
        output.pages = [
          for (var index = 0; index < source.pages.length; index++)
            pages.contains(index + 1)
                ? source.pages[index].rotatedBy(rotation)
                : source.pages[index],
        ];
        return _encodeValidateAndWrite(output, outputPath);
      } finally {
        await output.dispose();
      }
    } finally {
      await source.dispose();
    }
  }

  Future<PdfSafeWriteResult> deletePages({
    required String sourcePath,
    required Set<int> pages,
    required String outputPath,
  }) async {
    final source = await _open(sourcePath);
    try {
      _validatePages(pages.toList(), source.pages.length);
      if (pages.length >= source.pages.length) {
        throw ArgumentError('At least one page must remain in the PDF.');
      }
      final output = await PdfDocument.createNew(sourceName: outputPath);
      try {
        output.pages = [
          for (var index = 0; index < source.pages.length; index++)
            if (!pages.contains(index + 1)) source.pages[index],
        ];
        return _encodeValidateAndWrite(output, outputPath);
      } finally {
        await output.dispose();
      }
    } finally {
      await source.dispose();
    }
  }

  Future<PdfSafeWriteResult> duplicatePage({
    required String sourcePath,
    required int pageNumber,
    required String outputPath,
  }) async {
    final source = await _open(sourcePath);
    try {
      _validatePages([pageNumber], source.pages.length);
      final output = await PdfDocument.createNew(sourceName: outputPath);
      try {
        final pages = <PdfPage>[];
        for (var index = 0; index < source.pages.length; index++) {
          pages.add(source.pages[index]);
          if (index + 1 == pageNumber) pages.add(source.pages[index]);
        }
        output.pages = pages;
        return _encodeValidateAndWrite(output, outputPath);
      } finally {
        await output.dispose();
      }
    } finally {
      await source.dispose();
    }
  }

  Future<PdfSafeWriteResult> extractPages({
    required String sourcePath,
    required List<int> pages,
    required String outputPath,
  }) async {
    final source = await _open(sourcePath);
    try {
      _validatePages(pages, source.pages.length, allowDuplicates: true);
      final output = await PdfDocument.createNew(sourceName: outputPath);
      try {
        output.pages = [for (final number in pages) source.pages[number - 1]];
        return _encodeValidateAndWrite(output, outputPath);
      } finally {
        await output.dispose();
      }
    } finally {
      await source.dispose();
    }
  }

  Future<PdfSafeWriteResult> combine({
    required List<String> sourcePaths,
    required String outputPath,
  }) async {
    if (sourcePaths.length < 2) {
      throw ArgumentError('Select at least two PDFs to combine.');
    }
    final sources = <PdfDocument>[];
    PdfDocument? output;
    try {
      for (final path in sourcePaths) {
        sources.add(await _open(path));
      }
      output = await PdfDocument.createNew(sourceName: outputPath);
      output.pages = [for (final source in sources) ...source.pages];
      return await _encodeValidateAndWrite(output, outputPath);
    } finally {
      if (output != null) await output.dispose();
      for (final source in sources) {
        await source.dispose();
      }
    }
  }

  Future<List<PdfSafeWriteResult>> splitEachPage({
    required String sourcePath,
    required String outputDirectory,
    String baseName = 'page',
  }) async {
    final source = await _open(sourcePath);
    try {
      final results = <PdfSafeWriteResult>[];
      for (var index = 0; index < source.pages.length; index++) {
        final path = '$outputDirectory${Platform.pathSeparator}$baseName-${index + 1}.pdf';
        final output = await PdfDocument.createNew(sourceName: path);
        try {
          output.pages = [source.pages[index]];
          results.add(await _encodeValidateAndWrite(output, path));
        } finally {
          await output.dispose();
        }
      }
      return results;
    } finally {
      await source.dispose();
    }
  }

  Future<PdfSafeWriteResult> imagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
  }) async {
    if (imagePaths.isEmpty) throw ArgumentError('Select at least one image.');
    final imageDocs = <PdfDocument>[];
    PdfDocument? output;
    try {
      for (var index = 0; index < imagePaths.length; index++) {
        final bytes = await File(imagePaths[index]).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw ArgumentError('Unsupported image: ${imagePaths[index]}');
        }
        final jpeg = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
        final width = decoded.width.toDouble();
        final height = decoded.height.toDouble();
        imageDocs.add(await PdfDocument.createFromJpegData(
          jpeg,
          width: width,
          height: height,
          sourceName: 'image-${index + 1}.pdf',
        ));
      }
      output = await PdfDocument.createNew(sourceName: outputPath);
      output.pages = [for (final document in imageDocs) ...document.pages];
      return await _encodeValidateAndWrite(output, outputPath);
    } finally {
      if (output != null) await output.dispose();
      for (final document in imageDocs) {
        await document.dispose();
      }
    }
  }

  Future<PdfSafeWriteResult> safeReplaceOriginal({
    required String originalPath,
    required Uint8List pdfBytes,
  }) async {
    final original = File(originalPath);
    if (!await original.exists()) {
      throw ArgumentError('Original PDF does not exist: $originalPath');
    }
    final directory = original.parent.path;
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final tempPath = '$directory${Platform.pathSeparator}.lexpdf-$token.tmp.pdf';
    final backupPath = '$directory${Platform.pathSeparator}.lexpdf-$token.backup.pdf';
    final temp = File(tempPath);
    await temp.writeAsBytes(pdfBytes, flush: true);
    await _validatePdfFile(tempPath);

    await original.rename(backupPath);
    try {
      await temp.rename(originalPath);
      await _validatePdfFile(originalPath);
      return PdfSafeWriteResult(
        outputPath: originalPath,
        pageCount: await _pageCount(originalPath),
        backupPath: backupPath,
      );
    } catch (_) {
      final broken = File(originalPath);
      if (await broken.exists()) await broken.delete();
      final backup = File(backupPath);
      if (await backup.exists()) await backup.rename(originalPath);
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<PdfDocument> _open(String path) async {
    await pdfrxFlutterInitialize();
    return PdfDocument.openFile(path);
  }

  Future<PdfSafeWriteResult> _encodeValidateAndWrite(
    PdfDocument document,
    String outputPath,
  ) async {
    final bytes = await document.encodePdf();
    final output = File(outputPath);
    final directory = output.parent;
    if (!await directory.exists()) await directory.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final tempPath = '${directory.path}${Platform.pathSeparator}.lexpdf-$token.tmp.pdf';
    final temp = File(tempPath);
    await temp.writeAsBytes(bytes, flush: true);
    final pageCount = await _validatePdfFile(tempPath);
    if (await output.exists()) {
      throw StateError('Output already exists. Use another name to protect existing files.');
    }
    await temp.rename(outputPath);
    return PdfSafeWriteResult(outputPath: outputPath, pageCount: pageCount);
  }

  Future<int> _validatePdfFile(String path) async {
    final document = await _open(path);
    try {
      if (document.pages.isEmpty) throw StateError('Generated PDF has no pages.');
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  Future<int> _pageCount(String path) => _validatePdfFile(path);

  void _validatePages(
    List<int> pages,
    int pageCount, {
    bool allowDuplicates = false,
  }) {
    if (pages.isEmpty) throw ArgumentError('Select at least one page.');
    for (final page in pages) {
      if (page < 1 || page > pageCount) {
        throw ArgumentError.value(page, 'page', 'Page outside document range.');
      }
    }
    if (!allowDuplicates && pages.toSet().length != pages.length) {
      throw ArgumentError('Duplicate page numbers are not allowed.');
    }
  }
}
