import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

import '../storage/local_ocr_store.dart';
import '../storage/local_pdf_navigation_store.dart';

class PdfOcrProgress {
  const PdfOcrProgress({required this.pageNumber, required this.pageCount});
  final int pageNumber;
  final int pageCount;
}

class PdfOcrSummary {
  const PdfOcrSummary({
    required this.pageCount,
    required this.recognizedPages,
    required this.engine,
  });

  final int pageCount;
  final int recognizedPages;
  final String engine;
}

class MobilePdfOcrService {
  const MobilePdfOcrService({required this.ocrStore, required this.navigationStore});

  final LocalOcrStore ocrStore;
  final LocalPdfNavigationStore navigationStore;

  bool get nativeOcrSupported => Platform.isAndroid || Platform.isIOS;

  Future<PdfOcrSummary> process({
    required String documentId,
    required String filePath,
    void Function(PdfOcrProgress progress)? onProgress,
  }) async {
    final document = await PdfDocument.openFile(filePath);
    TextRecognizer? recognizer;
    final indexed = <int, String>{};
    var recognizedPages = 0;
    final engine = nativeOcrSupported ? 'mlkit-latin-offline' : 'embedded-text-fallback';

    try {
      if (nativeOcrSupported) {
        recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      }
      for (var index = 0; index < document.pages.length; index++) {
        final pageNumber = index + 1;
        final page = document.pages[index];
        String text;
        if (recognizer != null) {
          final rendered = await page.render(
            width: (page.width * 2).round(),
            height: (page.height * 2).round(),
            backgroundColor: 0xFFFFFFFF,
          );
          if (rendered == null) {
            text = '';
          } else {
            try {
              final input = InputImage.fromBitmap(
                bitmap: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
              );
              final recognized = await recognizer.processImage(input);
              text = recognized.text.trim();
            } finally {
              rendered.dispose();
            }
          }
        } else {
          final structured = await page.loadStructuredText();
          text = structured.fullText.trim();
        }

        if (text.isNotEmpty) recognizedPages++;
        indexed[pageNumber] = text;
        await ocrStore.upsert(
          OcrPageResult(
            documentId: documentId,
            pageNumber: pageNumber,
            text: text,
            engine: engine,
            processedAt: DateTime.now().toUtc(),
          ),
        );
        onProgress?.call(
          PdfOcrProgress(pageNumber: pageNumber, pageCount: document.pages.length),
        );
      }
      await navigationStore.replacePageTextIndex(
        documentId: documentId,
        pages: indexed,
      );
      return PdfOcrSummary(
        pageCount: document.pages.length,
        recognizedPages: recognizedPages,
        engine: engine,
      );
    } finally {
      await recognizer?.close();
      await document.dispose();
    }
  }
}
