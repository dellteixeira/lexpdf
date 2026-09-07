import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as gen;
import 'package:pdf/widgets.dart' as pw;
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

  Future<Uint8List> addBlankPage(
    String sourcePath, {
    int? afterPageNumber,
    double? width,
    double? height,
  }) async {
    final pageWidth = width ?? gen.PdfPageFormat.a4.width;
    final pageHeight = height ?? gen.PdfPageFormat.a4.height;
    final source = await PdfDocument.openFile(sourcePath);
    final blankFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lexpdf-blank-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final blankDocument = pw.Document();
    blankDocument.addPage(
      pw.Page(
        pageFormat: gen.PdfPageFormat(pageWidth, pageHeight, marginAll: 0),
        build: (_) => pw.Container(color: gen.PdfColors.white),
      ),
    );
    await blankFile.writeAsBytes(await blankDocument.save(), flush: true);
    final blank = await PdfDocument.openFile(blankFile.path);
    final output = await PdfDocument.createNew(sourceName: 'lexpdf-with-blank-page.pdf');
    try {
      final insertAfter = (afterPageNumber ?? source.pages.length)
          .clamp(0, source.pages.length)
          .toInt();
      output.pages = [
        ...source.pages.take(insertAfter),
        blank.pages.first,
        ...source.pages.skip(insertAfter),
      ];
      return await output.encodePdf();
    } finally {
      await output.dispose();
      await blank.dispose();
      await source.dispose();
      if (await blankFile.exists()) await blankFile.delete();
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

  Future<Uint8List> insertImageOnPage({
    required String sourcePath,
    required String imagePath,
    required int pageNumber,
    double leftFraction = 0.10,
    double topFraction = 0.10,
    double widthFraction = 0.35,
    double renderScale = 1.5,
  }) async {
    if (leftFraction < 0 || leftFraction > 1 ||
        topFraction < 0 || topFraction > 1 ||
        widthFraction <= 0 || widthFraction > 1) {
      throw ArgumentError('Image placement must use normalized page fractions.');
    }
    final source = await PdfDocument.openFile(sourcePath);
    final imageBytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw FormatException('Unsupported image: $imagePath');
    if (pageNumber < 1 || pageNumber > source.pages.length) {
      await source.dispose();
      throw RangeError.range(pageNumber, 1, source.pages.length, 'pageNumber');
    }

    final overlayBytes = Uint8List.fromList(img.encodePng(decoded));
    final overlay = pw.MemoryImage(overlayBytes);
    final output = pw.Document();
    try {
      for (final page in source.pages) {
        final render = await page.render(
          width: (page.width * renderScale).round().clamp(1, 10000),
          height: (page.height * renderScale).round().clamp(1, 10000),
          backgroundColor: 0xFFFFFFFF,
          annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
        );
        if (render == null) {
          throw StateError('Could not render page ${page.pageNumber}.');
        }
        late final Uint8List pagePng;
        try {
          pagePng = Uint8List.fromList(img.encodePng(render.createImageNF()));
        } finally {
          render.dispose();
        }
        final base = pw.MemoryImage(pagePng);
        final targetWidth = page.width * widthFraction;
        final targetHeight = targetWidth * decoded.height / decoded.width;
        output.addPage(
          pw.Page(
            pageFormat: gen.PdfPageFormat(page.width, page.height, marginAll: 0),
            build: (_) => pw.Stack(
              children: [
                pw.Image(base, width: page.width, height: page.height, fit: pw.BoxFit.fill),
                if (page.pageNumber == pageNumber)
                  pw.Positioned(
                    left: page.width * leftFraction,
                    top: page.height * topFraction,
                    child: pw.Image(
                      overlay,
                      width: targetWidth,
                      height: targetHeight,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
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
}
