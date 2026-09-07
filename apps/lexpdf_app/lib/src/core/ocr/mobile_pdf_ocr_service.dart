import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:platform_ocr/platform_ocr.dart';

import '../pdf/huge_pdf_policy.dart';
import '../storage/local_ocr_store.dart';
import '../storage/local_pdf_navigation_store.dart';

class PdfOcrProgress {
  const PdfOcrProgress({
    required this.pageNumber,
    required this.pageCount,
    this.skipped = false,
  });

  final int pageNumber;
  final int pageCount;
  final bool skipped;
}

class PdfOcrSummary {
  const PdfOcrSummary({
    required this.pageCount,
    required this.recognizedPages,
    required this.engine,
    this.skippedPages = 0,
    this.cancelled = false,
  });

  final int pageCount;
  final int recognizedPages;
  final String engine;
  final int skippedPages;
  final bool cancelled;
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

  /// Runs OCR with bounded per-page memory and incremental persistence.
  ///
  /// [resume] skips pages already processed by the same engine. [isCancelled]
  /// is checked between pages, so a 2,000+ page operation can be stopped
  /// without losing completed work.
  Future<PdfOcrSummary> process({
    required String documentId,
    required String filePath,
    void Function(PdfOcrProgress progress)? onProgress,
    bool resume = true,
    bool Function()? isCancelled,
  }) async {
    final document = await PdfDocument.openFile(filePath);
    TextRecognizer? recognizer;
    PlatformOcr? desktopOcr;
    var recognizedPages = 0;
    var skippedPages = 0;
    var cancelled = false;
    final engine = _engineName;

    try {
      if (mlKitOcrSupported) {
        recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      } else if (desktopNativeOcrSupported) {
        desktopOcr = PlatformOcr();
      }

      for (var index = 0; index < document.pages.length; index++) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }

        final pageNumber = index + 1;
        if (resume) {
          final existing = await ocrStore.getPage(documentId, pageNumber);
          if (existing != null && existing.engine == engine) {
            if (existing.text.trim().isNotEmpty) recognizedPages++;
            skippedPages++;
            await _upsertSearchIndex(
              documentId: documentId,
              pageNumber: pageNumber,
              text: existing.text,
            );
            onProgress?.call(
              PdfOcrProgress(
                pageNumber: pageNumber,
                pageCount: document.pages.length,
                skipped: true,
              ),
            );
            await _yieldIfNeeded(pageNumber);
            continue;
          }
        }

        final page = document.pages[index];
        String text;
        List<OcrTextLine> lines = const [];

        if (recognizer != null) {
          final size = HugePdfPolicy.boundedRenderSize(
            pageWidth: page.width,
            pageHeight: page.height,
          );
          final rendered = await page.render(
            width: size.width,
            height: size.height,
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
          final size = HugePdfPolicy.boundedRenderSize(
            pageWidth: page.width,
            pageHeight: page.height,
          );
          final rendered = await page.render(
            width: size.width,
            height: size.height,
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
        await _upsertSearchIndex(
          documentId: documentId,
          pageNumber: pageNumber,
          text: text,
        );
        onProgress?.call(
          PdfOcrProgress(
            pageNumber: pageNumber,
            pageCount: document.pages.length,
          ),
        );
        await _yieldIfNeeded(pageNumber);
      }

      return PdfOcrSummary(
        pageCount: document.pages.length,
        recognizedPages: recognizedPages,
        engine: engine,
        skippedPages: skippedPages,
        cancelled: cancelled,
      );
    } finally {
      await recognizer?.close();
      await document.dispose();
    }
  }

  Future<void> _upsertSearchIndex({
    required String documentId,
    required int pageNumber,
    required String text,
  }) async {
    navigationStore.db.database.execute('''
      INSERT INTO pdf_page_text_index(document_id, page_number, content, indexed_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(document_id, page_number) DO UPDATE SET
        content = excluded.content,
        indexed_at = excluded.indexed_at;
    ''', [
      documentId,
      pageNumber,
      text,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  Future<void> _yieldIfNeeded(int pageNumber) async {
    if (pageNumber % HugePdfPolicy.ocrYieldEveryPages == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}
