import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:platform_ocr/platform_ocr.dart';

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
  const MobilePdfOcrService({
    required this.ocrStore,
    required this.navigationStore,
  });

  final LocalOcrStore ocrStore;
  final LocalPdfNavigationStore navigationStore;

  bool get mlKitOcrSupported => Platform.isAndroid || Platform.isIOS;
  bool get desktopNativeOcrSupported => Platform.isWindows || Platform.isMacOS;
  bool get nativeOcrSupported => mlKitOcrSupported || desktopNativeOcrSupported;

  String get _engineName {
    if (mlKitOcrSupported) return 'mlkit-latin-offline';
    if (Platform.isWindows) return 'windows-media-ocr-offline';
    if (Platform.isMacOS) return 'apple-vision-ocr-offline';
    return 'embedded-text-fallback';
  }

  Future<PdfOcrSummary> process({
    required String documentId,
    required String filePath,
    void Function(PdfOcrProgress progress)? onProgress,
  }) async {
    final document = await PdfDocument.openFile(filePath);
    TextRecognizer? recognizer;
    PlatformOcr? desktopOcr;
    final indexed = <int, String>{};
    var recognizedPages = 0;
    final engine = _engineName;

    try {
      if (mlKitOcrSupported) {
        recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      } else if (desktopNativeOcrSupported) {
        desktopOcr = PlatformOcr();
      }

      for (var index = 0; index < document.pages.length; index++) {
        final pageNumber = index + 1;
        final page = document.pages[index];
        String text;
        List<OcrTextLine> lines = const [];

        if (recognizer != null) {
          final rendered = await page.render(
            width: (page.width * 2).round().clamp(1, 8000),
            height: (page.height * 2).round().clamp(1, 8000),
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
              final collected = <OcrTextLine>[];
              for (final block in recognized.blocks) {
                for (final line in block.lines) {
                  final box = line.boundingBox;
                  if (line.text.trim().isEmpty) continue;
                  collected.add(
                    OcrTextLine(
                      text: line.text.trim(),
                      x: (box.left / rendered.width).clamp(0.0, 1.0),
                      y: (box.top / rendered.height).clamp(0.0, 1.0),
                      width: (box.width / rendered.width).clamp(0.0, 1.0),
                      height: (box.height / rendered.height).clamp(0.0, 1.0),
                    ),
                  );
                }
              }
              lines = collected;
            } finally {
              rendered.dispose();
            }
          }
        } else if (desktopOcr != null) {
          final rendered = await page.render(
            width: (page.width * 2).round().clamp(1, 8000),
            height: (page.height * 2).round().clamp(1, 8000),
            backgroundColor: 0xFFFFFFFF,
          );
          if (rendered == null) {
            text = '';
          } else {
            try {
              final png = Uint8List.fromList(
                img.encodePng(rendered.createImageNF()),
              );
              final result = await desktopOcr.recognizeText(OcrSource.memory(png));
              text = result.text.trim();
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
            lines: lines,
          ),
        );
        onProgress?.call(
          PdfOcrProgress(
            pageNumber: pageNumber,
            pageCount: document.pages.length,
          ),
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
