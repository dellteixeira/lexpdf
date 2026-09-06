import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:platform_ocr/platform_ocr.dart';

import '../storage/local_pdf_navigation_store.dart';

class PdfOcrPageResult {
  const PdfOcrPageResult({
    required this.pageNumber,
    required this.text,
    required this.usedOcr,
  });

  final int pageNumber;
  final String text;
  final bool usedOcr;
}

class LocalPdfOcrService {
  LocalPdfOcrService({required this.searchStore});

  final LocalPdfNavigationStore searchStore;

  Future<List<PdfOcrPageResult>> recognizeDocument({
    required String documentId,
    required String filePath,
    void Function(int completed, int total)? onProgress,
    bool forceOcr = false,
  }) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(filePath);
    final indexed = <int, String>{};
    final results = <PdfOcrPageResult>[];
    try {
      for (var index = 0; index < document.pages.length; index++) {
        final page = document.pages[index];
        final extracted = await page.loadStructuredText();
        var text = extracted.fullText.trim();
        var usedOcr = false;
        if (forceOcr || text.length < 16) {
          final recognized = await _recognizeRenderedPage(page);
          if (recognized.trim().isNotEmpty) {
            text = recognized.trim();
            usedOcr = true;
          }
        }
        indexed[index + 1] = text;
        results.add(PdfOcrPageResult(
          pageNumber: index + 1,
          text: text,
          usedOcr: usedOcr,
        ));
        onProgress?.call(index + 1, document.pages.length);
      }
      await searchStore.replacePageTextIndex(
        documentId: documentId,
        pages: indexed,
      );
      return results;
    } finally {
      await document.dispose();
    }
  }

  Future<String> _recognizeRenderedPage(PdfPage page) async {
    final width = 1800.0;
    final height = width * page.height / page.width;
    final rendered = await page.render(
      width: width.round(),
      height: height.round(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (rendered == null) return '';
    try {
      final image = rendered.createImageNF();
      final png = img.encodePng(image);
      if (Platform.isAndroid) {
        return _recognizeAndroid(png);
      }
      if (Platform.isWindows || Platform.isMacOS || Platform.isIOS) {
        return _recognizeNative(png);
      }
      return '';
    } finally {
      rendered.dispose();
    }
  }

  Future<String> _recognizeAndroid(List<int> pngBytes) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}${Platform.pathSeparator}lexpdf-ocr-${DateTime.now().microsecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(pngBytes, flush: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
      return recognized.text;
    } finally {
      await recognizer.close();
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> _recognizeNative(List<int> pngBytes) async {
    final ocr = PlatformOcr();
    return ocr.recognizeText(OcrSource.memory(Uint8List.fromList(pngBytes)));
  }
}
