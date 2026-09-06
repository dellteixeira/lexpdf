import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

class PdfPageSpec {
  const PdfPageSpec({
    required this.sourcePath,
    required this.pageNumber,
    this.clockwiseQuarterTurns = 0,
  });

  final String sourcePath;
  final int pageNumber;
  final int clockwiseQuarterTurns;
}

class PdfPageManipulationService {
  const PdfPageManipulationService();

  Future<Uint8List> compose(
    List<PdfPageSpec> specs, {
    String sourceName = 'lexpdf-output.pdf',
  }) async {
    if (specs.isEmpty) throw ArgumentError('At least one PDF page is required.');
    final sourceDocuments = <String, PdfDocument>{};
    final output = await PdfDocument.createNew(sourceName: sourceName);
    try {
      final pages = <PdfPage>[];
      for (final spec in specs) {
        final document = sourceDocuments[spec.sourcePath] ??=
            await PdfDocument.openFile(spec.sourcePath);
        if (spec.pageNumber < 1 || spec.pageNumber > document.pages.length) {
          throw RangeError.range(
            spec.pageNumber,
            1,
            document.pages.length,
            'pageNumber',
          );
        }
        var page = document.pages[spec.pageNumber - 1];
        final turns = spec.clockwiseQuarterTurns % 4;
        if (turns == 1 || turns == -3) {
          page = page.rotatedCW90();
        } else if (turns == 2 || turns == -2) {
          page = page.rotated180();
        } else if (turns == 3 || turns == -1) {
          page = page.rotatedCCW90();
        }
        pages.add(page);
      }
      output.pages = pages;
      return await output.encodePdf();
    } finally {
      await output.dispose();
      for (final document in sourceDocuments.values) {
        await document.dispose();
      }
    }
  }

  Future<Uint8List> merge(
    List<String> sourcePaths, {
    String sourceName = 'lexpdf-combined.pdf',
  }) async {
    if (sourcePaths.isEmpty) throw ArgumentError('At least one PDF is required.');
    final documents = <PdfDocument>[];
    final output = await PdfDocument.createNew(sourceName: sourceName);
    try {
      for (final path in sourcePaths) {
        documents.add(await PdfDocument.openFile(path));
      }
      output.pages = [for (final document in documents) ...document.pages];
      if (output.pages.isEmpty) throw StateError('The selected PDFs contain no pages.');
      return await output.encodePdf();
    } finally {
      await output.dispose();
      for (final document in documents) {
        await document.dispose();
      }
    }
  }

  Future<List<Uint8List>> splitEveryPage(String sourcePath) async {
    final source = await PdfDocument.openFile(sourcePath);
    try {
      final outputs = <Uint8List>[];
      for (var index = 0; index < source.pages.length; index++) {
        final output = await PdfDocument.createNew(
          sourceName: 'page-${index + 1}.pdf',
        );
        try {
          output.pages = [source.pages[index]];
          outputs.add(await output.encodePdf());
        } finally {
          await output.dispose();
        }
      }
      return outputs;
    } finally {
      await source.dispose();
    }
  }

  Future<Uint8List> imagesToPdf(
    List<String> imagePaths, {
    String sourceName = 'images.pdf',
  }) async {
    if (imagePaths.isEmpty) throw ArgumentError('At least one image is required.');
    final imageDocuments = <PdfDocument>[];
    final output = await PdfDocument.createNew(sourceName: sourceName);
    try {
      for (final path in imagePaths) {
        final bytes = await File(path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw FormatException('Unsupported image: $path');
        }
        final jpeg = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
        const maxWidth = 595.0;
        const maxHeight = 842.0;
        final scale = [
          maxWidth / decoded.width,
          maxHeight / decoded.height,
          1.0,
        ].reduce((a, b) => a < b ? a : b);
        final width = decoded.width * scale;
        final height = decoded.height * scale;
        imageDocuments.add(
          await PdfDocument.createFromJpegData(
            jpeg,
            width: width,
            height: height,
            sourceName: path,
          ),
        );
      }
      output.pages = [for (final document in imageDocuments) ...document.pages];
      return await output.encodePdf();
    } finally {
      await output.dispose();
      for (final document in imageDocuments) {
        await document.dispose();
      }
    }
  }
}
