import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_models.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import '../widgets/pdf_ink_page_overlay.dart';

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

  late final Future<ReadingProgressState?> _initialProgress =
      widget.readingProgress.get(widget.document.id);
  final PdfViewerController _viewerController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  late final PdfTextSearcher _textSearcher =
      PdfTextSearcher(_viewerController)..addListener(_onSearchChanged);

  final Map<int, List<_RenderedAnnotation>> _renderedAnnotations = {};
  final Map<int, List<PdfInkStroke>> _pdfInkByPage = {};

  int? _currentPage;
  int _selectedAnnotationColor = _palette.first;
  int _inkColor = 0xFF246BFD;
  double _inkWidth = 3.0;
  InkTool _inkTool = InkTool.pen;
  bool _searchMode = false;
  bool _loadingAnnotations = false;
  bool _inkMode = false;
  bool _inkEraserMode = false;

  @override
  void dispose() {
    _textSearcher.removeListener(_onSearchChanged);
    _textSearcher.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
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
        actions: _searchMode ? _buildSearchActions() : _buildReaderActions(),
      ),
      body: FutureBuilder<ReadingProgressState?>(
        future: _initialProgress,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final initialPage = snapshot.data?.pageNumber ?? 1;
          _currentPage ??= initialPage;

          return Stack(
            children: [
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: PdfViewer.file(
                  path,
                  controller: _viewerController,
                  initialPageNumber: initialPage,
                  params: PdfViewerParams(
                    panEnabled: !_inkMode,
                    scaleEnabled: !_inkMode,
                    textSelectionParams: PdfTextSelectionParams(enabled: !_inkMode),
                    customizeContextMenuItems:
                        _inkMode ? null : _customizeContextMenuItems,
                    pagePaintCallbacks: [
                      _paintTextAnnotations,
                      _textSearcher.pageTextMatchPaintCallback,
                    ],
                    pageOverlaysBuilder: (context, pageRect, page) => [
                      Positioned.fill(
                        child: PdfInkPageOverlay(
                          key: ValueKey(
                            'pdf-ink-${page.pageNumber}-$_inkMode-$_inkEraserMode-${_pdfInkByPage[page.pageNumber]?.length ?? 0}',
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
                        ),
                      ),
                    ],
                    onViewerReady: (document, controller) {
                      unawaited(_loadSavedAnnotations(document));
                      unawaited(_loadPdfInk());
                    },
                    onPageChanged: (pageNumber) {
                      if (pageNumber == null) return;
                      if (_currentPage != pageNumber && mounted) {
                        setState(() => _currentPage = pageNumber);
                      }
                      unawaited(
                        widget.readingProgress.save(
                          documentId: widget.document.id,
                          pageNumber: pageNumber,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_inkMode)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _inkEraserMode ? Icons.auto_fix_off : Icons.edit,
                            color: _inkEraserMode ? null : Color(_inkColor),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _inkEraserMode
                                ? 'Borracha por traço'
                                : '${_inkToolLabel(_inkTool)} · ${_inkWidth.toStringAsFixed(1)}',
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _inkEraserMode ? null : _showInkSettings,
                            icon: const Icon(Icons.tune),
                            label: const Text('Ajustar'),
                          ),
                        ],
                      ),
                    ),
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
          );
        },
      ),
    );
  }

  double get _effectiveInkWidth => switch (_inkTool) {
        InkTool.pen => _inkWidth,
        InkTool.pencil => _inkWidth * 0.8,
        InkTool.highlighter => _inkWidth * 5,
      };

  List<Widget> _buildReaderActions() {
    final annotationCount = _renderedAnnotations.values.fold<int>(
      0,
      (sum, values) => sum + values.length,
    );
    final inkCount = _pdfInkByPage.values.fold<int>(
      0,
      (sum, values) => sum + values.length,
    );

    return [
      if (_currentPage != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(child: Text('Pág. $_currentPage')),
        ),
      IconButton(
        tooltip: _inkMode ? 'Sair do modo escrita' : 'Escrever no PDF',
        onPressed: _toggleInkMode,
        icon: Icon(_inkMode ? Icons.edit_off_outlined : Icons.edit_outlined),
        color: _inkMode ? Theme.of(context).colorScheme.primary : null,
      ),
      if (_inkMode) ...[
        IconButton(
          tooltip: _inkEraserMode ? 'Voltar para caneta' : 'Borracha por traço',
          onPressed: () {
            setState(() => _inkEraserMode = !_inkEraserMode);
            _viewerController.invalidate();
          },
          icon: Icon(
            _inkEraserMode ? Icons.edit_outlined : Icons.auto_fix_off,
          ),
          color: _inkEraserMode ? Theme.of(context).colorScheme.primary : null,
        ),
        IconButton(
          tooltip: 'Configurar caneta',
          onPressed: _inkEraserMode ? null : _showInkSettings,
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: 'Desfazer último traço desta página',
          onPressed: _undoPdfInk,
          icon: const Icon(Icons.undo),
        ),
      ] else ...[
        IconButton(
          tooltip: 'Pesquisar no PDF',
          onPressed: () => setState(() => _searchMode = true),
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: 'Cor das novas marcações',
          onPressed: _showColorPalette,
          icon: const Icon(Icons.palette_outlined),
        ),
        Badge(
          isLabelVisible: annotationCount > 0,
          label: Text('$annotationCount'),
          child: IconButton(
            tooltip: 'Anotações textuais',
            onPressed: _showAnnotationsPanel,
            icon: const Icon(Icons.draw_outlined),
          ),
        ),
      ],
      Badge(
        isLabelVisible: inkCount > 0,
        label: Text('$inkCount'),
        child: IconButton(
          tooltip: 'Traços manuscritos',
          onPressed: _showInkSummary,
          icon: const Icon(Icons.gesture_outlined),
        ),
      ),
      IconButton(
        tooltip: 'Imprimir',
        onPressed: null,
        icon: const Icon(Icons.print_outlined),
      ),
    ];
  }

  List<Widget> _buildSearchActions() {
    final currentIndex = _textSearcher.currentIndex;
    final matchCount = _textSearcher.matches.length;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: Text(
            _textSearcher.isSearching
                ? 'Buscando…'
                : matchCount == 0
                    ? '0 resultados'
                    : '${(currentIndex ?? 0) + 1}/$matchCount',
          ),
        ),
      ),
      IconButton(
        tooltip: 'Resultado anterior',
        onPressed: matchCount == 0
            ? null
            : () => unawaited(_textSearcher.goToPrevMatch()),
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        tooltip: 'Próximo resultado',
        onPressed: matchCount == 0
            ? null
            : () => unawaited(_textSearcher.goToNextMatch()),
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
      IconButton(
        tooltip: 'Fechar pesquisa',
        onPressed: _closeSearch,
        icon: const Icon(Icons.close),
      ),
    ];
  }

  void _toggleInkMode() {
    _textSearcher.resetTextSearch();
    _searchMode = false;
    setState(() {
      _inkMode = !_inkMode;
      if (!_inkMode) _inkEraserMode = false;
    });
    _viewerController.invalidate();
  }

  Future<void> _loadPdfInk() async {
    final strokes = await widget.pdfInkStore.listForDocument(widget.document.id);
    final byPage = <int, List<PdfInkStroke>>{};
    for (final stroke in strokes) {
      byPage.putIfAbsent(stroke.pageNumber, () => []).add(stroke);
    }
    if (!mounted) return;
    setState(() {
      _pdfInkByPage
        ..clear()
        ..addAll(byPage);
    });
    _viewerController.invalidate();
  }

  void _onPdfStrokeCompleted(PdfInkStroke stroke) {
    setState(() {
      _pdfInkByPage.putIfAbsent(stroke.pageNumber, () => []).add(stroke);
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
    setState(() {});
    unawaited(widget.pdfInkStore.deleteStroke(stroke.id));
    _viewerController.invalidate();
  }

  Future<void> _undoPdfInk() async {
    final page = _currentPage;
    if (page == null) return;
    final strokes = _pdfInkByPage[page];
    if (strokes == null || strokes.isEmpty) return;
    final removed = strokes.removeLast();
    await widget.pdfInkStore.deleteStroke(removed.id);
    if (mounted) setState(() {});
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
    final total =
        _pdfInkByPage.values.fold<int>(0, (sum, value) => sum + value.length);
    final pages = _pdfInkByPage.keys.toList()..sort();
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
                Text('Páginas: ${pages.join(', ')}'),
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
    if (_viewerController.isReady) {
      await _loadSavedAnnotations(_viewerController.document);
    }
  }

  Future<void> _loadSavedAnnotations(PdfDocument document) async {
    if (mounted) setState(() => _loadingAnnotations = true);
    try {
      final saved =
          await widget.annotations.listForDocument(widget.document.id);
      final byPage = <int, List<_RenderedAnnotation>>{};
      final pageTexts = <int, PdfPageText>{};
      for (final annotation in saved) {
        if (annotation.pageNumber < 1 ||
            annotation.pageNumber > document.pages.length) {
          continue;
        }
        final pageText = pageTexts[annotation.pageNumber] ??=
            await document.pages[annotation.pageNumber - 1]
                .loadStructuredText();
        if (annotation.startIndex > pageText.fullText.length ||
            annotation.endIndex > pageText.fullText.length) {
          continue;
        }
        byPage.putIfAbsent(annotation.pageNumber, () => []).add(
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
      _renderedAnnotations
        ..clear()
        ..addAll(byPage);
      _viewerController.invalidate();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _loadingAnnotations = false);
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
    if (_viewerController.isReady) {
      await _loadSavedAnnotations(_viewerController.document);
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
