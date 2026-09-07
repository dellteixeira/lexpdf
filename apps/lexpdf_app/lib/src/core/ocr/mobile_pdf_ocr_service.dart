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
    this.embeddedTextPages = 0,
    this.rasterizedPages = 0,
    this.cancelled = false,
  });

  final int pageCount;
  final int recognizedPages;
  final String engine;
  final int skippedPages;
  final int embeddedTextPages;
  final int rasterizedPages;
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

  /// Runs OCR with a bounded per-page working set and incremental persistence.
  ///
  /// For born-digital PDFs, embedded text is used before rasterization. This is
  /// both faster and dramatically cheaper in memory for 2,000–5,000+ pages.
  /// [resume] probes only page-number metadata, never all stored OCR text.
  /// [isCancelled] is checked before and after expensive page work so completed
  /// pages remain durable and a later run can resume without starting over.
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
    var embeddedTextPages = 0;
    var rasterizedPages = 0;
    var cancelled = false;
    final engine = _engineName;

    try {
      if (mlKitOcrSupported) {
        recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      } else if (desktopNativeOcrSupported) {
        desktopOcr = PlatformOcr();
      }

      final resumeState = resume
          ? await ocrStore.processedPageState(
              documentId,
              acceptedEngines: {engine, 'embedded-text'},
            )
          : const <int, bool>{};

      for (var index = 0; index < document.pages.length; index++) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }

        final pageNumber = index + 1;
        final alreadyProcessed = resumeState[pageNumber];
        if (alreadyProcessed != null) {
          if (alreadyProcessed) recognizedPages++;
          skippedPages++;
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

        final page = document.pages[index];
        String text = '';
        String pageEngine = engine;
        List<OcrTextLine> lines = const [];

        final embedded = await _loadEmbeddedText(page);
        if (embedded.length >= HugePdfPolicy.ocrEmbeddedTextMinChars ||
            !nativeOcrSupported) {
          text = embedded;
          pageEngine = 'embedded-text';
          embeddedTextPages++;
        } else if (recognizer != null) {
          final size = HugePdfPolicy.boundedRenderSize(
            pageWidth: page.width,
            pageHeight: page.height,
            maxPixels: HugePdfPolicy.ocrMaxPixels,
          );
          final rendered = await page.render(
            width: size.width,
            height: size.height,
            backgroundColor: 0xFFFFFFFF,
          );
          if (rendered != null) {
            rasterizedPages++;
            try {
              if (isCancelled?.call() == true) {
                cancelled = true;
                break;
              }
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
            maxPixels: HugePdfPolicy.ocrDesktopMaxPixels,
          );
          final rendered = await page.render(
            width: size.width,
            height: size.height,
            backgroundColor: 0xFFFFFFFF,
          );
          if (rendered != null) {
            rasterizedPages++;
            try {
              if (isCancelled?.call() == true) {
                cancelled = true;
                break;
              }
              final png = Uint8List.fromList(
                img.encodePng(rendered.createImageNF()),
              );
              final result = await desktopOcr.recognizeText(OcrSource.memory(png));
              text = result.text.trim();
            } finally {
              rendered.dispose();
            }
          }
        }

        if (cancelled) break;
        if (text.isNotEmpty) recognizedPages++;
        await ocrStore.upsert(
          OcrPageResult(
            documentId: documentId,
            pageNumber: pageNumber,
            text: text,
            engine: pageEngine,
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

        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }
      }

      return PdfOcrSummary(
        pageCount: document.pages.length,
        recognizedPages: recognizedPages,
        engine: engine,
        skippedPages: skippedPages,
        embeddedTextPages: embeddedTextPages,
        rasterizedPages: rasterizedPages,
        cancelled: cancelled,
      );
    } finally {
      await recognizer?.close();
      await document.dispose();
    }
  }

  Future<String> _loadEmbeddedText(PdfPage page) async {
    try {
      final structured = await page.loadStructuredText();
      return structured.fullText.trim();
    } catch (_) {
      return '';
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
