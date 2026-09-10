import 'dart:async';

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

  final String documentId;
  final LocalTextAnnotationStore store;
  final PdfViewerController controller;
  final int Function() colorValue;
  final VoidCallback onChanged;

  final Map<int, List<_RenderedTextAnnotation>> _rendered =
      <int, List<_RenderedTextAnnotation>>{};
  PdfDocument? _document;

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
      const ContextMenuButtonItem(
        label: 'Recortar',
        onPressed: null,
      ),
      const ContextMenuButtonItem(
        label: 'Colar',
        onPressed: null,
      ),
      ContextMenuButtonItem(
        label: 'Marca-texto',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_annotate(delegate, TextAnnotationType.highlight));
        },
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
          unawaited(delegate.clearTextSelection());
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

  Future<void> _annotate(
    PdfTextSelectionDelegate delegate,
    TextAnnotationType type,
  ) async {
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
        colorValue: type == TextAnnotationType.highlight
            ? 0xFFFFD54F
            : colorValue(),
        opacity: type == TextAnnotationType.highlight ? 0.28 : 1.0,
        createdAt: now,
        updatedAt: now,
      );
      await store.upsert(annotation);
    }
    final document = _document;
    if (document != null) await load(document);
    await delegate.clearTextSelection();
    controller.invalidate();
  }

  void paint(Canvas canvas, Rect pageRect, PdfPage page) {
    final annotations = _rendered[page.pageNumber];
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
              Paint()
                ..color = color.withValues(alpha: annotation.opacity)
                ..blendMode = BlendMode.multiply,
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
}

class _RenderedTextAnnotation {
  const _RenderedTextAnnotation({
    required this.annotation,
    required this.range,
  });

  final LocalTextAnnotation annotation;
  final PdfPageTextRange range;
}
