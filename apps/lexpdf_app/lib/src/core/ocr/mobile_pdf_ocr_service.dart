import 'dart:async';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:platform_ocr/platform_ocr.dart';

import '../pdf/huge_pdf_policy.dart';
import '../storage/local_global_search_fts.dart';
import '../storage/local_ocr_store.dart';
import '../storage/local_pdf_navigation_store.dart';

class PdfOcrProgress {
  const PdfOcrProgress({
    required this.pageNumber,
    required this.pageCount,
    this.skipped = false,
    this.completedInRange = 0,
    this.totalInRange = 0,
  });

  final int pageNumber;
  final int pageCount;
  final bool skipped;
  final int completedInRange;
  final int totalInRange;
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
    this.startPage = 1,
    this.endPage,
  });

  final int pageCount;
  final int recognizedPages;
  final String engine;
  final int skippedPages;
  final int embeddedTextPages;
  final int rasterizedPages;
  final bool cancelled;
  final int startPage;
  final int? endPage;
}

class PdfTextAvailability {
  const PdfTextAvailability({
    required this.pageCount,
    required this.sampledPages,
    required this.pagesWithUsefulText,
    required this.charactersFound,
  });

  final int pageCount;
  final int sampledPages;
  final int pagesWithUsefulText;
  final int charactersFound;

  bool get likelyScanned => sampledPages > 0 && pagesWithUsefulText == 0;
  bool get hasUsefulText => pagesWithUsefulText > 0;
}

class MobilePdfOcrService {
  const MobilePdfOcrService({
    required this.ocrStore,
    required this.navigationStore,
  });

  final LocalOcrStore ocrStore;
  final LocalPdfNavigationStore navigationStore;

  bool get mlKitOcrSupported => Platform.isAndroid || Platform.isIOS;
  bool get desktopNativeOcrSupported => Platform.isWindows;
  bool get nativeOcrSupported => mlKitOcrSupported || desktopNativeOcrSupported;

  Set<String> get resumeEngines => {_engineName, 'embedded-text'};

  String get _engineName {
    if (mlKitOcrSupported) return 'mlkit-latin-offline';
    if (Platform.isWindows) return 'windows-media-ocr-offline';
    return 'embedded-text-fallback';
  }

  /// Samples only a small bounded set of pages. It never rasterizes and never
  /// loads every page's text into memory merely to decide whether OCR is useful.
  Future<PdfTextAvailability> inspectTextAvailability({
    required String filePath,
    int maxSamplePages = 4,
  }) async {
    final document = await PdfDocument.openFile(filePath);
    try {
      final count = document.pages.length;
      if (count == 0 || maxSamplePages <= 0) {
        return PdfTextAvailability(
          pageCount: count,
          sampledPages: 0,
          pagesWithUsefulText: 0,
          charactersFound: 0,
        );
      }
      final sampleCount = maxSamplePages.clamp(1, count);
      final indexes = <int>{0};
      if (sampleCount > 1) {
        for (var i = 1; i < sampleCount; i++) {
          indexes.add(((count - 1) * i / (sampleCount - 1)).round());
        }
      }
      var useful = 0;
      var characters = 0;
      for (final index in indexes) {
        final text = await _loadEmbeddedText(document.pages[index]);
        characters += text.length;
        if (text.length >= HugePdfPolicy.ocrEmbeddedTextMinChars) useful++;
        await Future<void>.delayed(Duration.zero);
      }
      return PdfTextAvailability(
        pageCount: count,
        sampledPages: indexes.length,
        pagesWithUsefulText: useful,
        charactersFound: characters,
      );
    } finally {
      await document.dispose();
    }
  }

  /// Runs OCR with a bounded per-page working set and incremental persistence.
  ///
  /// [startPage] and [endPage] allow selective OCR. Completed pages remain
  /// durable, and [resume] skips pages already processed by a compatible engine.
  Future<PdfOcrSummary> process({
    required String documentId,
    String? filePath,
    PdfDocument? openedDocument,
    void Function(PdfOcrProgress progress)? onProgress,
    bool resume = true,
    bool Function()? isCancelled,
    int startPage = 1,
    int? endPage,
  }) async {
    if (openedDocument == null && (filePath == null || filePath.isEmpty)) {
      throw ArgumentError(
        'Either filePath or openedDocument must be provided.',
      );
    }
    final ownsDocument = openedDocument == null;
    final document = openedDocument ?? await PdfDocument.openFile(filePath!);
    TextRecognizer? recognizer;
    PlatformOcr? desktopOcr;
    var recognizedPages = 0;
    var skippedPages = 0;
    var embeddedTextPages = 0;
    var rasterizedPages = 0;
    var cancelled = false;
    final engine = _engineName;
    final pageCount = document.pages.length;
    final safeStart = pageCount == 0 ? 1 : startPage.clamp(1, pageCount);
    final requestedEnd = endPage ?? pageCount;
    final safeEnd = pageCount == 0 ? 0 : requestedEnd.clamp(safeStart, pageCount);
    final rangeTotal = safeEnd < safeStart ? 0 : safeEnd - safeStart + 1;
    var completedInRange = 0;
    final fts = LocalGlobalSearchFts(navigationStore.db);

    try {
      if (mlKitOcrSupported) {
        recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      } else if (desktopNativeOcrSupported) {
        desktopOcr = PlatformOcr();
      }

      final resumeState = resume
          ? await ocrStore.processedPageState(
              documentId,
              acceptedEngines: resumeEngines,
            )
          : const <int, bool>{};

      for (var pageNumber = safeStart; pageNumber <= safeEnd; pageNumber++) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }

        final alreadyProcessed = resumeState[pageNumber];
        if (alreadyProcessed != null) {
          if (alreadyProcessed) recognizedPages++;
          skippedPages++;
          completedInRange++;
          onProgress?.call(
            PdfOcrProgress(
              pageNumber: pageNumber,
              pageCount: pageCount,
              skipped: true,
              completedInRange: completedInRange,
              totalInRange: rangeTotal,
            ),
          );
          await _yieldIfNeeded(pageNumber);
          continue;
        }

        final page = document.pages[pageNumber - 1];
        String text = '';
        String pageEngine = engine;
        List<OcrTextLine> lines = const [];

        final embedded = await _loadEmbeddedText(page);
        // Any embedded text means this page already has a native text layer.
        // OCR is reserved for pages with no extractable text at all. This avoids
        // rasterizing short title/blank pages in otherwise searchable PDFs.
        if (embedded.isNotEmpty || !nativeOcrSupported) {
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
              try {
                // pdfrx exposes rendered RGBA pixels, while ML Kit's bitmap
                // bridge is format-sensitive on Android. Encode a real PNG and
                // let the native decoder read it from a temporary file instead
                // of handing arbitrary raw RGBA pixels to the native bridge.
                final temporaryDirectory = await getTemporaryDirectory();
                final temporaryFile = File(
                  '${temporaryDirectory.path}'
                  '${Platform.pathSeparator}'
                  'lexpdf-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
                );
                try {
                  final png = img.encodePng(rendered.createImageNF());
                  await temporaryFile.writeAsBytes(png, flush: true);
                  final recognized = await recognizer.processImage(
                    InputImage.fromFilePath(temporaryFile.path),
                  );
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
                  if (await temporaryFile.exists()) {
                    await temporaryFile.delete();
                  }
                }
              } catch (_) {
                // A single problematic raster must not abort the whole
                // background index. Persist an empty processed page below so
                // the same failure does not loop every time the PDF is opened.
                text = '';
                lines = const [];
              }
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
              final png = img.encodePng(rendered.createImageNF());
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
        await fts.upsertPdfPage(
          documentId: documentId,
          pageNumber: pageNumber,
          content: text,
        );
        completedInRange++;
        onProgress?.call(
          PdfOcrProgress(
            pageNumber: pageNumber,
            pageCount: pageCount,
            completedInRange: completedInRange,
            totalInRange: rangeTotal,
          ),
        );
        await _yieldIfNeeded(pageNumber);

        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }
      }

      return PdfOcrSummary(
        pageCount: pageCount,
        recognizedPages: recognizedPages,
        engine: engine,
        skippedPages: skippedPages,
        embeddedTextPages: embeddedTextPages,
        rasterizedPages: rasterizedPages,
        cancelled: cancelled,
        startPage: safeStart,
        endPage: safeEnd,
      );
    } finally {
      await recognizer?.close();
      if (ownsDocument) {
        await document.dispose();
      }
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
