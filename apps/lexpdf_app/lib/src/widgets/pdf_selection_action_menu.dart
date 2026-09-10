import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/storage/local_text_annotation_store.dart';

/// Selection actions shared by the unified PDF workspace.
///
/// PDF page text is immutable in the viewer, so destructive cut/paste are
/// intentionally exposed as disabled actions rather than pretending to edit
/// the PDF content stream. Copy and text-markup actions are fully functional.
class PdfSelectionActionMenu {
  PdfSelectionActionMenu({
    required this.documentId,
    required this.store,
    required this.controller,
    required this.colorValue,
    required this.onChanged,
  });

  static const _highlightPalette = <int>[
    0xFFFFD54F,
    0xFFFFFF00,
    0xFF81C784,
    0xFF64B5F6,
    0xFFF48FB1,
    0xFFFFB74D,
    0xFFBA68C8,
    0xFF26C6DA,
  ];

  final String documentId;
  final LocalTextAnnotationStore store;
  final PdfViewerController controller;
  final int Function() colorValue;
  final VoidCallback onChanged;

  final Map<int, List<_RenderedTextAnnotation>> _rendered =
      <int, List<_RenderedTextAnnotation>>{};
  PdfDocument? _document;
  int _highlightColorValue = _highlightPalette.first;
  double _highlightOpacity = 0.28;

  Future<void> load(PdfDocument document) async {
    _document = document;
    final annotations = await store.listForDocument(documentId);
    final pageTexts = <int, PdfPageText>{};
    final rendered = <int, List<_RenderedTextAnnotation>>{};

    for (final annotation in annotations) {
      if (annotation.pageNumber < 1 ||
          annotation.pageNumber > document.pages.length) {
        continue;
      }

      final text = pageTexts[annotation.pageNumber] ??=
          await document.pages[annotation.pageNumber - 1].loadStructuredText();
      if (annotation.startIndex < 0 ||
          annotation.startIndex > text.fullText.length ||
          annotation.endIndex < annotation.startIndex ||
          annotation.endIndex > text.fullText.length) {
        continue;
      }

      final range = PdfPageTextRange(
        pageText: text,
        start: annotation.startIndex,
        end: annotation.endIndex,
      );

      // Computing fragment geometry can be expensive. Do it once when the
      // annotation model is loaded instead of during every page repaint. On
      // Windows a repaint may be requested for every pan/zoom frame; doing text
      // layout work there caused severe frame starvation and visible smearing.
      final fragmentBounds = range
          .enumerateFragmentBoundingRects()
          .map((fragment) => fragment.bounds)
          .toList(growable: false);

      rendered.putIfAbsent(annotation.pageNumber, () => []).add(
            _RenderedTextAnnotation(
              annotation: annotation,
              fragmentBounds: fragmentBounds,
            ),
          );
    }

    _rendered
      ..clear()
      ..addAll(rendered);
    onChanged();
  }

  Widget? buildContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final delegate = params.textSelectionDelegate;
    if (!params.isTextSelectionEnabled || !delegate.hasSelectedText) {
      return null;
    }

    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        type: ContextMenuButtonType.copy,
        onPressed: delegate.isCopyAllowed
            ? () {
                params.dismissContextMenu();
                unawaited(delegate.copyTextSelection());
              }
            : null,
      ),
      const ContextMenuButtonItem(label: 'Recortar', onPressed: null),
      const ContextMenuButtonItem(label: 'Colar', onPressed: null),
      ContextMenuButtonItem(
        label: 'Marca-texto',
        onPressed: () => unawaited(
          _configureAndApplyHighlight(context, params, delegate),
        ),
      ),
      ContextMenuButtonItem(
        label: 'Sublinhado',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_annotate(delegate, TextAnnotationType.underline));
        },
      ),
      ContextMenuButtonItem(
        label: 'Tachado',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_annotate(delegate, TextAnnotationType.strikeout));
        },
      ),
      ContextMenuButtonItem(
        label: 'Limpar seleção',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_clearMarkupInSelection(delegate));
        },
      ),
    ];

    return Align(
      alignment: Alignment.topLeft,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: params.anchorA,
          secondaryAnchor: params.anchorB,
        ),
        buttonItems: items,
      ),
    );
  }

  Future<void> _configureAndApplyHighlight(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
    PdfTextSelectionDelegate delegate,
  ) async {
    final style = await _showHighlightStyleDialog(context);
    if (style == null) return;

    _highlightColorValue = style.colorValue;
    _highlightOpacity = style.opacity;
    params.dismissContextMenu();
    await _annotate(
      delegate,
      TextAnnotationType.highlight,
      colorOverride: style.colorValue,
      opacityOverride: style.opacity,
    );
  }

  Future<_HighlightStyle?> _showHighlightStyleDialog(BuildContext context) {
    var color = _highlightColorValue;
    var opacity = _highlightOpacity;

    return showDialog<_HighlightStyle>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configurar marca-texto'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cor'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final value in _highlightPalette)
                      Tooltip(
                        message: value == color ? 'Cor selecionada' : 'Escolher cor',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => setDialogState(() => color = value),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(value),
                              border: Border.all(
                                color: value == color
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outlineVariant,
                                width: value == color ? 3 : 1,
                              ),
                            ),
                            child: value == color
                                ? Icon(
                                    Icons.check,
                                    size: 20,
                                    color: ThemeData.estimateBrightnessForColor(
                                              Color(value),
                                            ) ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text('Opacidade: ${(opacity * 100).round()}%'),
                Slider(
                  min: 0.10,
                  max: 0.80,
                  divisions: 14,
                  value: opacity,
                  label: '${(opacity * 100).round()}%',
                  onChanged: (value) =>
                      setDialogState(() => opacity = value),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Color(color).withValues(alpha: opacity),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Prévia do marca-texto',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _HighlightStyle(colorValue: color, opacity: opacity),
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _annotate(
    PdfTextSelectionDelegate delegate,
    TextAnnotationType type, {
    int? colorOverride,
    double? opacityOverride,
  }) async {
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final now = DateTime.now().toUtc();

    for (var i = 0; i < ranges.length; i++) {
      final range = ranges[i];
      final annotation = LocalTextAnnotation(
        id: 'selection-${now.microsecondsSinceEpoch.toRadixString(36)}-$i',
        documentId: documentId,
        pageNumber: range.pageNumber,
        startIndex: range.start,
        endIndex: range.end,
        type: type,
        selectedText: range.text,
        colorValue: colorOverride ??
            (type == TextAnnotationType.highlight
                ? _highlightColorValue
                : colorValue()),
        opacity: opacityOverride ??
            (type == TextAnnotationType.highlight ? _highlightOpacity : 1.0),
        createdAt: now,
        updatedAt: now,
      );
      await store.upsert(annotation);
    }

    await _refreshAfterMarkupChange(delegate);
  }

  Future<void> _clearMarkupInSelection(
    PdfTextSelectionDelegate delegate,
  ) async {
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) {
      await delegate.clearTextSelection();
      return;
    }

    final deletedIds = <String>{};
    for (final range in ranges) {
      final annotations = await store.listForPage(documentId, range.pageNumber);
      for (final annotation in annotations) {
        final overlaps = annotation.startIndex < range.end &&
            annotation.endIndex > range.start;
        if (!overlaps || !deletedIds.add(annotation.id)) continue;
        await store.delete(annotation.id);
      }
    }

    await _refreshAfterMarkupChange(delegate);
  }

  Future<void> _refreshAfterMarkupChange(
    PdfTextSelectionDelegate delegate,
  ) async {
    final document = _document;
    if (document != null) await load(document);
    await delegate.clearTextSelection();
    controller.invalidate();
  }

  void paint(Canvas canvas, Rect pageRect, PdfPage page) {
    final annotations = _rendered[page.pageNumber];
    if (annotations == null || annotations.isEmpty) return;

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    for (final rendered in annotations) {
      final annotation = rendered.annotation;
      final color = Color(annotation.colorValue);

      for (final bounds in rendered.fragmentBounds) {
        final rect = bounds.toRectInDocument(page: page, pageRect: pageRect);
        switch (annotation.type) {
          case TextAnnotationType.highlight:
            final paint = Paint()
              ..color = color.withValues(
                alpha: isWindows
                    ? (annotation.opacity * 0.78).clamp(0.0, 1.0)
                    : annotation.opacity,
              )
              ..style = PaintingStyle.fill;
            // Avoid non-default blend operations in the Windows PDF page paint
            // callback. The page is already rasterized by PDFium; srcOver keeps
            // the text readable with translucency without forcing an extra
            // compositor path while the page is moving.
            if (!isWindows) paint.blendMode = BlendMode.multiply;
            canvas.drawRect(rect, paint);
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
}

class _HighlightStyle {
  const _HighlightStyle({
    required this.colorValue,
    required this.opacity,
  });

  final int colorValue;
  final double opacity;
}

class _RenderedTextAnnotation {
  const _RenderedTextAnnotation({
    required this.annotation,
    required this.fragmentBounds,
  });

  final LocalTextAnnotation annotation;
  final List<PdfRect> fragmentBounds;
}
