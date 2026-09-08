import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_eraser.dart';
import '../core/ink/pdf_ink_models.dart';
import '../core/pdf/huge_pdf_policy.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import '../widgets/pdf_ink_page_overlay.dart';
import '../widgets/pdf_reader_controls.dart';
import 'ai_study_screen.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    required this.document,
    required this.readingProgress,
    required this.annotations,
    required this.pdfInkStore,
    super.key,
  });

  final DocumentRef document;
  final LocalReadingProgressStore readingProgress;
  final LocalTextAnnotationStore annotations;
  final LocalPdfInkStore pdfInkStore;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _RenderedAnnotation {
  const _RenderedAnnotation({required this.annotation, required this.range});
  final LocalTextAnnotation annotation;
  final PdfPageTextRange range;
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  static const _palette = <int>[
    0xFFFFD54F,
    0xFF81C784,
    0xFF64B5F6,
    0xFFF48FB1,
    0xFFFFB74D,
    0xFFBA68C8,
    0xFFEF5350,
    0xFF26C6DA,
    0xFF1C1B1F,
  ];

  final PdfViewerController _viewerController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  late final PdfTextSearcher _textSearcher =
      PdfTextSearcher(_viewerController)..addListener(_onSearchChanged);

  final Map<int, List<_RenderedAnnotation>> _renderedAnnotations = {};
  final Map<int, List<PdfInkStroke>> _pdfInkByPage = {};

  Timer? _progressSaveTimer;
  Timer? _deferredOverlayLoadTimer;
  PdfDocument? _activeDocument;
  int _overlayLoadGeneration = 0;
  int _annotationCount = 0;
  int _inkCount = 0;
  int _restoredPage = 1;
  int? _currentPage = 1;
  int _selectedAnnotationColor = _palette.first;
  int _inkColor = 0xFF246BFD;
  double _inkWidth = 3.0;
  InkTool _inkTool = InkTool.pen;
  bool _viewerReady = false;
  bool _searchMode = false;
  bool _loadingAnnotations = false;
  bool _inkMode = false;
  bool _inkEraserMode = false;

  bool get _mobileTouchNavigationEnabled =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreReadingProgress());
    unawaited(_loadCounts());
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _deferredOverlayLoadTimer?.cancel();
    _overlayLoadGeneration++;
    final page = _currentPage;
    if (page != null) {
      unawaited(
        widget.readingProgress.save(
          documentId: widget.document.id,
          pageNumber: page,
        ),
      );
    }
    _textSearcher.removeListener(_onSearchChanged);
    _textSearcher.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreReadingProgress() async {
    final saved = await widget.readingProgress.get(widget.document.id);
    _restoredPage = saved?.pageNumber ?? 1;
    if (_restoredPage < 1) _restoredPage = 1;
    if (_viewerReady && _viewerController.isReady) {
      await _goToRestoredPage();
    }
  }

  Future<void> _goToRestoredPage() async {
    if (!_viewerController.isReady || _restoredPage <= 1) return;
    final count = _viewerController.document.pages.length;
    if (count < 1) return;
    final target = _restoredPage.clamp(1, count);
    await _viewerController.goToPage(
      pageNumber: target,
      anchor: PdfPageAnchor.top,
    );
  }

  void _scheduleProgressSave(int pageNumber) {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        widget.readingProgress.save(
          documentId: widget.document.id,
          pageNumber: pageNumber,
        ),
      );
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCounts() async {
    final values = await Future.wait<int>([
      widget.annotations.countForDocument(widget.document.id),
      widget.pdfInkStore.countForDocument(widget.document.id),
    ]);
    if (!mounted) return;
    setState(() {
      _annotationCount = values[0];
      _inkCount = values[1];
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.document.name)),
        body: const Center(
          child: Text('Este documento ainda não está disponível offline.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Pesquisar no documento',
                  border: InputBorder.none,
                ),
                onSubmitted: _startSearch,
              )
            : Text(
                widget.document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          if (_searchMode)
            PdfSearchAppBarActions(
              isSearching: _textSearcher.isSearching,
              currentIndex: _textSearcher.currentIndex,
              matchCount: _textSearcher.matches.length,
              onPrevious: _textSearcher.matches.isEmpty
                  ? null
                  : () => unawaited(_textSearcher.goToPrevMatch()),
              onNext: _textSearcher.matches.isEmpty
                  ? null
                  : () => unawaited(_textSearcher.goToNextMatch()),
              onClose: _closeSearch,
            )
          else
            PdfReaderAppBarActions(
              currentPage: _currentPage,
              inkMode: _inkMode,
              inkEraserMode: _inkEraserMode,
              annotationCount: _annotationCount,
              inkCount: _inkCount,
              onToggleInkMode: _toggleInkMode,
              onToggleEraser: _toggleInkEraser,
              onConfigureInk: _inkEraserMode ? null : _showInkSettings,
              onUndoInk: () => unawaited(_undoPdfInk()),
              onOpenStudy: () => unawaited(_openDocumentStudy()),
              onOpenSearch: () => setState(() => _searchMode = true),
              onOpenAnnotationPalette: () => unawaited(_showColorPalette()),
              onOpenAnnotations: () => unawaited(_showAnnotationsPanel()),
              onOpenInkSummary: () => unawaited(_showInkSummary()),
            ),
        ],
      ),
      body: Stack(
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: PdfViewer.file(
              path,
              controller: _viewerController,
              initialPageNumber: 1,
              useProgressiveLoading: true,
              params: PdfViewerParams(
                limitRenderingCache: true,
                maxImageBytesCachedOnMemory: HugePdfPolicy.viewerImageCacheBytes,
                horizontalCacheExtent: 0.30,
                verticalCacheExtent: 0.30,
                onePassRenderingSizeThreshold: 1400,
                behaviorControlParams: const PdfViewerBehaviorControlParams(
                  loadPageDimensionsOnDemand: true,
                  enableLowResolutionPagePreview: true,
                  trailingPageLoadingDelay: Duration(milliseconds: 250),
                  pageImageCachingDelay: Duration(milliseconds: 40),
                  partialImageLoadingDelay: Duration(milliseconds: 60),
                ),
                // On phones/tablets, touch remains dedicated to navigation even
                // while the ink overlay is active. The overlay accepts stylus,
                // inverted stylus and mouse input, so a two-finger pinch can
                // zoom the page without leaving writing mode.
                panEnabled: !_inkMode || _mobileTouchNavigationEnabled,
                scaleEnabled: !_inkMode || _mobileTouchNavigationEnabled,
                textSelectionParams: PdfTextSelectionParams(enabled: !_inkMode),
                customizeContextMenuItems:
                    _inkMode ? null : _customizeContextMenuItems,
                loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                    const Center(child: CircularProgressIndicator()),
                errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                    Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, size: 42),
                        const SizedBox(height: 12),
                        const Text(
                          'Não foi possível renderizar este PDF.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '$error',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                pagePaintCallbacks: [
                  _paintTextAnnotations,
                  _textSearcher.pageTextMatchPaintCallback,
                ],
                pageOverlaysBuilder: (context, pageRect, page) => [
                  Positioned.fill(
                    child: PdfInkPageOverlay(
                      key: ValueKey(
                        'pdf-ink-${page.pageNumber}-$_inkMode-$_inkEraserMode',
                      ),
                      documentId: widget.document.id,
                      pageNumber: page.pageNumber,
                      strokes: _pdfInkByPage[page.pageNumber] ?? const [],
                      enabled: _inkMode,
                      tool: _inkTool,
                      colorValue: _inkColor,
                      strokeWidth: _effectiveInkWidth,
                      eraserMode: _inkEraserMode,
                      onStrokeCompleted: _onPdfStrokeCompleted,
                      onStrokeErased: _onPdfStrokeErased,
                      onEraseApplied: _onPdfEraseApplied,
                    ),
                  ),
                ],
                onViewerReady: (document, controller) {
                  _viewerReady = true;
                  _activeDocument = document;
                  unawaited(_goToRestoredPage());
                  _deferredOverlayLoadTimer?.cancel();
                  _deferredOverlayLoadTimer =
                      Timer(const Duration(milliseconds: 160), () {
                    if (!mounted || !_viewerController.isReady) return;
                    unawaited(_loadOverlayWindow(document, _restoredPage));
                  });
                },
                onPageChanged: (pageNumber) {
                  if (pageNumber == null) return;
                  if (_currentPage != pageNumber && mounted) {
                    setState(() => _currentPage = pageNumber);
                  }
                  _scheduleProgressSave(pageNumber);
                  final document = _activeDocument;
                  if (document != null) {
                    unawaited(_loadOverlayWindow(document, pageNumber));
                  }
                },
              ),
            ),
          ),
          if (_inkMode)
            Positioned(
              left: 16,
              bottom: 16,
              child: PdfInkStatusCard(
                eraserMode: _inkEraserMode,
                colorValue: _inkColor,
                toolLabel: _inkToolLabel(_inkTool),
                width: _inkWidth,
                onConfigure: _inkEraserMode ? null : _showInkSettings,
              ),
            ),
          if (_loadingAnnotations)
            const Positioned(
              right: 16,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Carregando anotações'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double get _effectiveInkWidth => switch (_inkTool) {
        InkTool.pen => _inkWidth,
        InkTool.pencil => _inkWidth * 0.8,
        InkTool.highlighter => _inkWidth * 5,
      };

  void _toggleInkMode() {
    _textSearcher.resetTextSearch();
    _searchMode = false;
    setState(() {
      _inkMode = !_inkMode;
      if (!_inkMode) _inkEraserMode = false;
    });
    _viewerController.invalidate();
  }

  void _toggleInkEraser() {
    setState(() => _inkEraserMode = !_inkEraserMode);
    _viewerController.invalidate();
  }

  Future<void> _loadOverlayWindow(
    PdfDocument document,
    int pageNumber,
  ) async {
    final generation = ++_overlayLoadGeneration;
    final window = HugePdfPolicy.overlayWindow(
      pageNumber: pageNumber,
      pageCount: document.pages.length,
    );
    if (window.end < window.start) return;

    if (mounted) setState(() => _loadingAnnotations = true);
    try {
      final results = await Future.wait<Object>([
        widget.annotations.listForPageRange(
          widget.document.id,
          window.start,
          window.end,
        ),
        widget.pdfInkStore.listForPageRange(
          widget.document.id,
          window.start,
          window.end,
        ),
      ]);
      if (!mounted || generation != _overlayLoadGeneration) return;

      final saved = results[0] as List<LocalTextAnnotation>;
      final strokes = results[1] as List<PdfInkStroke>;
      final byAnnotationPage = <int, List<_RenderedAnnotation>>{};
      final pageTexts = <int, PdfPageText>{};
      for (final annotation in saved) {
        if (annotation.pageNumber < window.start ||
            annotation.pageNumber > window.end) {
          continue;
        }
        final pageText = pageTexts[annotation.pageNumber] ??=
            await document.pages[annotation.pageNumber - 1]
                .loadStructuredText();
        if (!mounted || generation != _overlayLoadGeneration) return;
        if (annotation.startIndex > pageText.fullText.length ||
            annotation.endIndex > pageText.fullText.length) {
          continue;
        }
        byAnnotationPage.putIfAbsent(annotation.pageNumber, () => []).add(
              _RenderedAnnotation(
                annotation: annotation,
                range: PdfPageTextRange(
                  pageText: pageText,
                  start: annotation.startIndex,
                  end: annotation.endIndex,
                ),
              ),
            );
      }

      final byInkPage = <int, List<PdfInkStroke>>{};
      for (final stroke in strokes) {
        byInkPage.putIfAbsent(stroke.pageNumber, () => []).add(stroke);
      }
      if (!mounted || generation != _overlayLoadGeneration) return;

      setState(() {
        _renderedAnnotations
          ..removeWhere(
            (page, _) => page < window.start || page > window.end,
          )
          ..addAll(byAnnotationPage);
        for (var page = window.start; page <= window.end; page++) {
          if (!byAnnotationPage.containsKey(page)) {
            _renderedAnnotations.remove(page);
          }
        }

        _pdfInkByPage
          ..removeWhere(
            (page, _) => page < window.start || page > window.end,
          )
          ..addAll(byInkPage);
        for (var page = window.start; page <= window.end; page++) {
          if (!byInkPage.containsKey(page)) {
            _pdfInkByPage.remove(page);
          }
        }
      });
      _viewerController.invalidate();
    } finally {
      if (mounted && generation == _overlayLoadGeneration) {
        setState(() => _loadingAnnotations = false);
      }
    }
  }

  void _onPdfStrokeCompleted(PdfInkStroke stroke) {
    setState(() {
      _pdfInkByPage.putIfAbsent(stroke.pageNumber, () => []).add(stroke);
      _inkCount++;
    });
    unawaited(widget.pdfInkStore.addStroke(stroke));
  }

  void _onPdfStrokeErased(PdfInkStroke stroke) {
    final strokes = _pdfInkByPage[stroke.pageNumber];
    if (strokes == null) return;
    final previousLength = strokes.length;
    strokes.removeWhere((candidate) => candidate.id == stroke.id);
    if (strokes.length == previousLength) return;
    if (strokes.isEmpty) {
      _pdfInkByPage.remove(stroke.pageNumber);
    }
    setState(() {
      if (_inkCount > 0) _inkCount--;
    });
    unawaited(widget.pdfInkStore.deleteStroke(stroke.id));
    _viewerController.invalidate();
  }

  void _onPdfEraseApplied(PdfInkEraseResult result) {
    final strokes = _pdfInkByPage[result.original.pageNumber];
    if (strokes == null) return;
    final index = strokes.indexWhere((stroke) => stroke.id == result.original.id);
    if (index < 0) return;

    strokes
      ..removeAt(index)
      ..insertAll(index, result.fragments);
    if (strokes.isEmpty) {
      _pdfInkByPage.remove(result.original.pageNumber);
    }
    setState(() {
      _inkCount = (_inkCount - 1 + result.fragments.length).clamp(0, 1 << 31);
    });
    unawaited(
      widget.pdfInkStore.replaceStrokeWithFragments(
        result.original,
        result.fragments,
      ),
    );
    _viewerController.invalidate();
  }

  Future<void> _undoPdfInk() async {
    final page = _currentPage;
    if (page == null) return;
    final strokes = _pdfInkByPage[page];
    if (strokes == null || strokes.isEmpty) return;
    final removed = strokes.removeLast();
    await widget.pdfInkStore.deleteStroke(removed.id);
    if (mounted) {
      setState(() {
        if (_inkCount > 0) _inkCount--;
      });
    }
    _viewerController.invalidate();
  }

  Future<void> _showInkSettings() async {
    var tool = _inkTool;
    var color = _inkColor;
    var width = _inkWidth;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Caneta sobre PDF',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                SegmentedButton<InkTool>(
                  segments: const [
                    ButtonSegment(
                      value: InkTool.pen,
                      icon: Icon(Icons.edit),
                      label: Text('Caneta'),
                    ),
                    ButtonSegment(
                      value: InkTool.pencil,
                      icon: Icon(Icons.draw_outlined),
                      label: Text('Lápis'),
                    ),
                    ButtonSegment(
                      value: InkTool.highlighter,
                      icon: Icon(Icons.border_color_outlined),
                      label: Text('Marca-texto'),
                    ),
                  ],
                  selected: {tool},
                  onSelectionChanged: (value) =>
                      setSheetState(() => tool = value.first),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final value in _palette)
                      InkWell(
                        onTap: () => setSheetState(() => color = value),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: value == color
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Espessura: ${width.toStringAsFixed(1)}'),
                Slider(
                  min: 1,
                  max: 10,
                  value: width,
                  onChanged: (value) =>
                      setSheetState(() => width = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _inkTool = tool;
                        _inkColor = color;
                        _inkWidth = width;
                        _inkEraserMode = false;
                      });
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInkSummary() async {
    final total = await widget.pdfInkStore.countForDocument(widget.document.id);
    final pages = await widget.pdfInkStore.pagesWithInk(widget.document.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escrita manuscrita',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text('$total traços em ${pages.length} página(s).'),
              if (pages.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  pages.length <= 40
                      ? 'Páginas: ${pages.join(', ')}'
                      : 'Páginas: ${pages.take(40).join(', ')}… (+${pages.length - 40})',
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Os traços são vetoriais, ficam salvos offline e não alteram o PDF original.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _inkToolLabel(InkTool tool) => switch (tool) {
        InkTool.pen => 'Caneta',
        InkTool.pencil => 'Lápis',
        InkTool.highlighter => 'Marca-texto',
      };

  void _customizeContextMenuItems(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    if (!params.textSelectionDelegate.hasSelectedText) return;
    items.addAll([
      ContextMenuButtonItem(
        label: 'Estudar',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_studyCurrentSelection());
        },
      ),
      ContextMenuButtonItem(
        label: 'Grifar',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_saveCurrentSelection(TextAnnotationType.highlight));
        },
      ),
      ContextMenuButtonItem(
        label: 'Sublinhar',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_saveCurrentSelection(TextAnnotationType.underline));
        },
      ),
      ContextMenuButtonItem(
        label: 'Tachar',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_saveCurrentSelection(TextAnnotationType.strikeout));
        },
      ),
    ]);
  }

  Future<void> _studyCurrentSelection() async {
    final delegate = _viewerController.textSelectionDelegate;
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty || !mounted) return;
    final selected = ranges
        .map((range) => range.text.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
    await delegate.clearTextSelection();
    if (selected.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiStudyScreen(
          initialText: selected,
          title: 'Estudar seleção',
        ),
      ),
    );
  }

  Future<void> _openDocumentStudy() async {
    final path = widget.document.localPath;
    if (path == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiStudyScreen(
          documentPath: path,
          title: 'Estudar ${widget.document.name}',
        ),
      ),
    );
  }

  Future<void> _saveCurrentSelection(TextAnnotationType type) async {
    final delegate = _viewerController.textSelectionDelegate;
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final now = DateTime.now().toUtc();
    final baseId = now.microsecondsSinceEpoch.toRadixString(36);
    final opacity = type == TextAnnotationType.highlight ? 0.35 : 1.0;
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      await widget.annotations.upsert(
        LocalTextAnnotation(
          id: '$baseId-$index',
          documentId: widget.document.id,
          pageNumber: range.pageNumber,
          startIndex: range.start,
          endIndex: range.end,
          type: type,
          selectedText: range.text,
          colorValue: _selectedAnnotationColor,
          opacity: opacity,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await delegate.clearTextSelection();
    await _loadCounts();
    final document = _activeDocument;
    final page = _currentPage;
    if (document != null && page != null) {
      await _loadOverlayWindow(document, page);
    }
  }

  void _paintTextAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    final annotations = _renderedAnnotations[page.pageNumber];
    if (annotations == null || annotations.isEmpty) return;
    for (final rendered in annotations) {
      final annotation = rendered.annotation;
      final color = Color(annotation.colorValue);
      for (final fragment in rendered.range.enumerateFragmentBoundingRects()) {
        final rect =
            fragment.bounds.toRectInDocument(page: page, pageRect: pageRect);
        switch (annotation.type) {
          case TextAnnotationType.highlight:
            canvas.drawRect(
              rect,
              Paint()..color = color.withValues(alpha: annotation.opacity),
            );
          case TextAnnotationType.underline:
            canvas.drawLine(
              Offset(rect.left, rect.bottom - 1),
              Offset(rect.right, rect.bottom - 1),
              Paint()
                ..color = color
                ..strokeWidth = 2,
            );
          case TextAnnotationType.strikeout:
            canvas.drawLine(
              Offset(rect.left, rect.center.dy),
              Offset(rect.right, rect.center.dy),
              Paint()
                ..color = color
                ..strokeWidth = 2,
            );
        }
      }
    }
  }

  Future<void> _showColorPalette() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final value in _palette)
                InkWell(
                  onTap: () => Navigator.of(context).pop(value),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() => _selectedAnnotationColor = chosen);
    }
  }

  Future<void> _showAnnotationsPanel() async {
    final annotations =
        await widget.annotations.listForDocument(widget.document.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: annotations.isEmpty
              ? const Center(child: Text('Nenhuma anotação textual.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: annotations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final annotation = annotations[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 12,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(annotation.colorValue),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        title: Text(
                          annotation.selectedText?.trim().isNotEmpty == true
                              ? annotation.selectedText!.trim()
                              : _annotationTypeLabel(annotation.type),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_annotationTypeLabel(annotation.type)} · Página ${annotation.pageNumber}',
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(
                            _viewerController.goToPage(
                              pageNumber: annotation.pageNumber,
                              anchor: PdfPageAnchor.center,
                            ),
                          );
                        },
                        trailing: IconButton(
                          tooltip: 'Excluir anotação',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_deleteAnnotation(annotation.id));
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _annotationTypeLabel(TextAnnotationType type) => switch (type) {
        TextAnnotationType.highlight => 'Grifo',
        TextAnnotationType.underline => 'Sublinhado',
        TextAnnotationType.strikeout => 'Tachado',
      };

  Future<void> _deleteAnnotation(String id) async {
    await widget.annotations.delete(id);
    await _loadCounts();
    final document = _activeDocument;
    final page = _currentPage;
    if (document != null && page != null) {
      await _loadOverlayWindow(document, page);
    }
  }

  void _startSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _textSearcher.resetTextSearch();
      return;
    }
    _textSearcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
  }

  void _closeSearch() {
    _textSearcher.resetTextSearch();
    _searchController.clear();
    setState(() => _searchMode = false);
  }
}
