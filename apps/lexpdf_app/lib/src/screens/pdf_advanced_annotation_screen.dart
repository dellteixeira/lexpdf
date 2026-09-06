import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/annotations/pdf_annotation_object.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_text_annotation_store.dart';
import '../widgets/pdf_annotation_object_overlay.dart';

class PdfAdvancedAnnotationScreen extends StatefulWidget {
  const PdfAdvancedAnnotationScreen({
    required this.document,
    required this.annotations,
    super.key,
  });

  final DocumentRef document;
  final LocalTextAnnotationStore annotations;

  @override
  State<PdfAdvancedAnnotationScreen> createState() =>
      _PdfAdvancedAnnotationScreenState();
}

class _RenderedTextAnnotation {
  const _RenderedTextAnnotation({required this.annotation, required this.range});
  final LocalTextAnnotation annotation;
  final PdfPageTextRange range;
}

class _PdfAdvancedAnnotationScreenState
    extends State<PdfAdvancedAnnotationScreen> {
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

  final PdfViewerController _controller = PdfViewerController();
  final Map<int, List<_RenderedTextAnnotation>> _renderedText = {};
  bool _editMode = true;
  bool _loading = false;
  int _color = 0xFF246BFD;
  int _revision = 0;
  int? _currentPage;

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Anotações avançadas')),
        body: const Center(
          child: Text('O PDF precisa estar disponível offline.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Anotações avançadas'),
            Text(
              widget.document.name,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_currentPage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('Pág. $_currentPage')),
            ),
          IconButton(
            tooltip: _editMode ? 'Navegar no PDF' : 'Editar anotações',
            onPressed: () {
              setState(() => _editMode = !_editMode);
              _controller.invalidate();
            },
            icon: Icon(
              _editMode ? Icons.pan_tool_outlined : Icons.edit_note_outlined,
            ),
            color: _editMode ? Theme.of(context).colorScheme.primary : null,
          ),
          IconButton(
            tooltip: 'Cor atual',
            onPressed: _showPalette,
            icon: Icon(Icons.palette_outlined, color: Color(_color)),
          ),
          IconButton(
            tooltip: 'Painel unificado de anotações',
            onPressed: _showUnifiedPanel,
            icon: const Icon(Icons.view_list_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer.file(
            path,
            controller: _controller,
            params: PdfViewerParams(
              panEnabled: !_editMode,
              scaleEnabled: !_editMode,
              textSelectionParams:
                  PdfTextSelectionParams(enabled: !_editMode),
              pagePaintCallbacks: [_paintTextAnnotations],
              pageOverlaysBuilder: (context, pageRect, page) => [
                Positioned.fill(
                  child: PdfAnnotationObjectOverlay(
                    key: ValueKey(
                      'advanced-${page.pageNumber}-$_revision-$_editMode',
                    ),
                    documentId: widget.document.id,
                    pageNumber: page.pageNumber,
                    store: widget.annotations.objectStore,
                    enabled: _editMode,
                    colorValue: _color,
                    onChanged: () => setState(() => _revision++),
                  ),
                ),
              ],
              onViewerReady: (document, controller) {
                unawaited(_loadTextAnnotations(document));
              },
              onPageChanged: (pageNumber) {
                if (pageNumber != null && mounted) {
                  setState(() => _currentPage = pageNumber);
                }
              },
            ),
          ),
          if (_loading)
            const Positioned(
              right: 16,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Atualizando anotações'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showPalette() async {
    final selected = await showModalBottomSheet<int>(
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
                      border: Border.all(
                        color: value == _color
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _color = selected);
  }

  Future<void> _loadTextAnnotations(PdfDocument document) async {
    setState(() => _loading = true);
    try {
      final annotations =
          await widget.annotations.listForDocument(widget.document.id);
      final pageTexts = <int, PdfPageText>{};
      final rendered = <int, List<_RenderedTextAnnotation>>{};
      for (final annotation in annotations) {
        if (annotation.pageNumber < 1 ||
            annotation.pageNumber > document.pages.length) {
          continue;
        }
        final text = pageTexts[annotation.pageNumber] ??=
            await document.pages[annotation.pageNumber - 1]
                .loadStructuredText();
        if (annotation.startIndex > text.fullText.length ||
            annotation.endIndex > text.fullText.length) {
          continue;
        }
        rendered.putIfAbsent(annotation.pageNumber, () => []).add(
              _RenderedTextAnnotation(
                annotation: annotation,
                range: PdfPageTextRange(
                  pageText: text,
                  start: annotation.startIndex,
                  end: annotation.endIndex,
                ),
              ),
            );
      }
      _renderedText
        ..clear()
        ..addAll(rendered);
      _controller.invalidate();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _paintTextAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    final annotations = _renderedText[page.pageNumber];
    if (annotations == null) return;
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

  Future<void> _showUnifiedPanel() async {
    final text = await widget.annotations.listForDocument(widget.document.id);
    final objects =
        await widget.annotations.objectStore.listForDocument(widget.document.id);
    if (!mounted) return;

    final items = <_PanelItem>[
      for (final annotation in text)
        _PanelItem.text(
          pageNumber: annotation.pageNumber,
          title: _textTypeLabel(annotation.type),
          subtitle: annotation.selectedText?.trim(),
          id: annotation.id,
        ),
      for (final object in objects)
        _PanelItem.object(
          pageNumber: object.pageNumber,
          title: _objectTypeLabel(object.type),
          subtitle: object.textValue?.trim(),
          id: object.id,
        ),
    ]..sort((a, b) {
        final page = a.pageNumber.compareTo(b.pageNumber);
        if (page != 0) return page;
        return a.title.compareTo(b.title);
      });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.70,
          child: items.isEmpty
              ? const Center(child: Text('Nenhuma anotação neste PDF.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          item.isObject
                              ? Icons.category_outlined
                              : Icons.format_color_fill,
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          [
                            'Página ${item.pageNumber}',
                            if (item.subtitle?.isNotEmpty == true) item.subtitle!,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(
                            _controller.goToPage(
                              pageNumber: item.pageNumber,
                              anchor: PdfPageAnchor.center,
                            ),
                          );
                        },
                        trailing: IconButton(
                          tooltip: 'Excluir anotação',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (item.isObject) {
                              await widget.annotations.objectStore.delete(item.id);
                            } else {
                              await widget.annotations.delete(item.id);
                            }
                            if (!mounted) return;
                            Navigator.of(sheetContext).pop();
                            setState(() => _revision++);
                            if (_controller.isReady) {
                              await _loadTextAnnotations(_controller.document);
                            }
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

  String _textTypeLabel(TextAnnotationType type) => switch (type) {
        TextAnnotationType.highlight => 'Grifo',
        TextAnnotationType.underline => 'Sublinhado',
        TextAnnotationType.strikeout => 'Tachado',
      };

  String _objectTypeLabel(PdfAnnotationObjectType type) => switch (type) {
        PdfAnnotationObjectType.note => 'Nota adesiva',
        PdfAnnotationObjectType.text => 'Caixa de texto',
        PdfAnnotationObjectType.line => 'Linha',
        PdfAnnotationObjectType.arrow => 'Seta',
        PdfAnnotationObjectType.rectangle => 'Retângulo',
        PdfAnnotationObjectType.ellipse => 'Elipse',
        PdfAnnotationObjectType.stamp => 'Carimbo',
        PdfAnnotationObjectType.signature => 'Assinatura textual',
      };
}

class _PanelItem {
  const _PanelItem({
    required this.pageNumber,
    required this.title,
    required this.id,
    required this.isObject,
    this.subtitle,
  });

  factory _PanelItem.text({
    required int pageNumber,
    required String title,
    required String id,
    String? subtitle,
  }) =>
      _PanelItem(
        pageNumber: pageNumber,
        title: title,
        id: id,
        isObject: false,
        subtitle: subtitle,
      );

  factory _PanelItem.object({
    required int pageNumber,
    required String title,
    required String id,
    String? subtitle,
  }) =>
      _PanelItem(
        pageNumber: pageNumber,
        title: title,
        id: id,
        isObject: true,
        subtitle: subtitle,
      );

  final int pageNumber;
  final String title;
  final String? subtitle;
  final String id;
  final bool isObject;
}
