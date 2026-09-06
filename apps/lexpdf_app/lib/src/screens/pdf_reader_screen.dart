import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    required this.document,
    required this.readingProgress,
    required this.annotations,
    super.key,
  });

  final DocumentRef document;
  final LocalReadingProgressStore readingProgress;
  final LocalTextAnnotationStore annotations;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _RenderedAnnotation {
  const _RenderedAnnotation({
    required this.annotation,
    required this.range,
  });

  final LocalTextAnnotation annotation;
  final PdfPageTextRange range;
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  static const _annotationPalette = <int>[
    0xFFFFD54F,
    0xFF81C784,
    0xFF64B5F6,
    0xFFF48FB1,
    0xFFFFB74D,
    0xFFBA68C8,
    0xFFEF5350,
    0xFF26C6DA,
  ];

  late final Future<ReadingProgressState?> _initialProgress =
      widget.readingProgress.get(widget.document.id);
  final PdfViewerController _viewerController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  late final PdfTextSearcher _textSearcher =
      PdfTextSearcher(_viewerController)..addListener(_onSearchChanged);

  final Map<int, List<_RenderedAnnotation>> _renderedAnnotations = {};

  int? _currentPage;
  int _selectedAnnotationColor = _annotationPalette.first;
  bool _searchMode = false;
  bool _loadingAnnotations = false;

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
                    textSelectionParams:
                        const PdfTextSelectionParams(enabled: true),
                    customizeContextMenuItems: _customizeContextMenuItems,
                    pagePaintCallbacks: [
                      _paintTextAnnotations,
                      _textSearcher.pageTextMatchPaintCallback,
                    ],
                    onViewerReady: (document, controller) {
                      unawaited(_loadSavedAnnotations(document));
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

  List<Widget> _buildReaderActions() {
    final annotationCount = _renderedAnnotations.values.fold<int>(
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
        tooltip: 'Pesquisar no PDF',
        onPressed: () => setState(() => _searchMode = true),
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: 'Cor das novas marcações',
        onPressed: _showColorPalette,
        icon: Stack(
          alignment: Alignment.bottomRight,
          children: [
            const Icon(Icons.palette_outlined),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Color(_selectedAnnotationColor),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface),
              ),
            ),
          ],
        ),
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
      if (_textSearcher.isSearching)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(
              matchCount == 0
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
      final annotation = LocalTextAnnotation(
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
      );
      await widget.annotations.upsert(annotation);
    }

    await delegate.clearTextSelection();
    if (_viewerController.isReady) {
      await _loadSavedAnnotations(_viewerController.document);
    }
  }

  Future<void> _loadSavedAnnotations(PdfDocument document) async {
    if (mounted) setState(() => _loadingAnnotations = true);
    try {
      final saved = await widget.annotations.listForDocument(widget.document.id);
      final byPage = <int, List<_RenderedAnnotation>>{};
      final pageTexts = <int, PdfPageText>{};

      for (final annotation in saved) {
        if (annotation.pageNumber < 1 ||
            annotation.pageNumber > document.pages.length) {
          continue;
        }
        final pageText = pageTexts[annotation.pageNumber] ??=
            await document.pages[annotation.pageNumber - 1].loadStructuredText();
        if (annotation.startIndex > pageText.fullText.length ||
            annotation.endIndex > pageText.fullText.length) {
          continue;
        }
        final range = PdfPageTextRange(
          pageText: pageText,
          start: annotation.startIndex,
          end: annotation.endIndex,
        );
        byPage.putIfAbsent(annotation.pageNumber, () => []).add(
              _RenderedAnnotation(annotation: annotation, range: range),
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
        final rect = fragment.bounds.toRectInDocument(
          page: page,
          pageRect: pageRect,
        );
        switch (annotation.type) {
          case TextAnnotationType.highlight:
            canvas.drawRect(
              rect,
              Paint()
                ..color = color.withValues(alpha: annotation.opacity)
                ..style = PaintingStyle.fill,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cor das novas marcações',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final value in _annotationPalette)
                    InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => Navigator.of(context).pop(value),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: value == _selectedAnnotationColor
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 4,
                                )
                              : null,
                        ),
                        child: value == _selectedAnnotationColor
                            ? const Icon(Icons.check, color: Colors.black87)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'O grifo usa transparência para manter o texto totalmente legível.',
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
    final annotations = await widget.annotations.listForDocument(widget.document.id);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Anotações (${annotations.length})',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: annotations.isEmpty
                    ? const Center(
                        child: Text(
                          'Selecione um texto no PDF para criar a primeira marcação.',
                        ),
                      )
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
            ],
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
