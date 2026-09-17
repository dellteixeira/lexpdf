import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/ai/ai_models.dart';
import '../core/annotations/pdf_annotation_object.dart';
import '../core/storage/local_study_notebook_store.dart';
import '../core/storage/local_text_annotation_store.dart';

typedef PdfSelectionStudyAction = Future<void> Function(
  BuildContext context,
  String selectedText,
  AiStudyAction action,
);

/// Selection actions shared by the unified PDF workspace.
///
/// PDF page text is immutable in the viewer, so destructive cut/paste remain
/// visible but disabled. Copy, markup, notes and study actions work on the
/// selected text without changing the PDF content stream.
class PdfSelectionActionMenu {
  PdfSelectionActionMenu({
    required this.documentId,
    required this.store,
    required this.controller,
    required this.colorValue,
    required this.onChanged,
    this.onStudyAction,
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
  final PdfSelectionStudyAction? onStudyAction;

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
        label: 'Destacar',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_annotate(delegate, TextAnnotationType.highlight));
        },
      ),
      ContextMenuButtonItem(
        label: 'Anotar',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_createNoteFromSelection(context, delegate));
        },
      ),
      ContextMenuButtonItem(
        label: 'Flashcard',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(_createManualFlashcard(context, delegate));
        },
      ),
      if (onStudyAction != null)
        ContextMenuButtonItem(
          label: 'Explicar com IA',
          onPressed: () {
            params.dismissContextMenu();
            unawaited(_explainSelectionWithAi(context, delegate));
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

  Future<void> _explainSelectionWithAi(
    BuildContext context,
    PdfTextSelectionDelegate delegate,
  ) async {
    final callback = onStudyAction;
    if (callback == null) return;
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final selectedText = _selectionText(ranges);
    if (selectedText.isEmpty) return;
    await delegate.clearTextSelection();
    if (!context.mounted) return;
    await callback(context, selectedText, AiStudyAction.explain);
  }

  Future<void> _createManualFlashcard(
    BuildContext context,
    PdfTextSelectionDelegate delegate,
  ) async {
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final selectedText = _selectionText(ranges);
    if (selectedText.isEmpty) return;

    final draft = await _showManualFlashcardDialog(
      context,
      selectedText: selectedText,
    );
    if (draft == null) return;
    if (draft.question.trim().isEmpty || draft.answer.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preencha pergunta e resposta do flashcard.')),
        );
      }
      return;
    }

    final rows = store.db.database.select(
      'SELECT title, filename FROM documents WHERE id = ? LIMIT 1;',
      [documentId],
    );
    final row = rows.isEmpty ? null : rows.first;
    final title = (row?['title'] as String?)?.trim();
    final filename = (row?['filename'] as String?)?.trim();
    final documentTitle = title?.isNotEmpty == true
        ? title!
        : (filename?.isNotEmpty == true ? filename! : 'PDF');

    await LocalStudyNotebookStore(store.db).saveResult(
      documentId: documentId,
      documentTitle: documentTitle,
      sourcePage: ranges.first.pageNumber,
      result: AiStudyResult(
        action: AiStudyAction.flashcards,
        engine: AiEngineKind.local,
        sourceText: selectedText,
        flashcards: [
          AiFlashcard(
            question: draft.question.trim(),
            answer: draft.answer.trim(),
          ),
        ],
      ),
    );
    await delegate.clearTextSelection();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flashcard salvo.')),
      );
    }
  }

  Future<void> _createNoteFromSelection(
    BuildContext context,
    PdfTextSelectionDelegate delegate,
  ) async {
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final selectedText = _selectionText(ranges);
    if (selectedText.isEmpty) return;

    final content = await _showSelectionNoteEditor(
      context,
      selectedText: selectedText,
    );
    if (content == null || content.text.trim().isEmpty) return;

    final pageNumber = ranges.first.pageNumber;
    var x = 0.05;
    var y = 0.05;
    final document = _document;
    if (document != null && pageNumber >= 1 && pageNumber <= document.pages.length) {
      final fragments = ranges.first.enumerateFragmentBoundingRects().toList(growable: false);
      if (fragments.isNotEmpty) {
        final page = document.pages[pageNumber - 1];
        final bounds = fragments.first.bounds;
        x = (bounds.left / page.width).clamp(0.02, 0.98).toDouble();
        y = ((page.height - bounds.top) / page.height).clamp(0.02, 0.98).toDouble();
      }
    }

    final now = DateTime.now().toUtc();
    await store.objectStore.upsert(
      PdfAnnotationObject(
        id: 'selection-note-${now.microsecondsSinceEpoch.toRadixString(36)}',
        documentId: documentId,
        pageNumber: pageNumber,
        type: PdfAnnotationObjectType.note,
        x: x,
        y: y,
        width: 0.03,
        height: 0.03,
        colorValue: 0xFF7A5B00,
        fillColorValue: 0xFFFFD54F,
        opacity: 1.0,
        strokeWidth: 1.2,
        textValue: content.encode(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await delegate.clearTextSelection();
    onChanged();
    controller.invalidate();
  }

  String _selectionText(List<PdfPageTextRange> ranges) {
    return ranges
        .map((range) => range.text.trim())
        .where((text) => text.isNotEmpty)
        .join('\n')
        .trim();
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

class _ManualFlashcardDraft {
  const _ManualFlashcardDraft({required this.question, required this.answer});
  final String question;
  final String answer;
}

Future<_ManualFlashcardDraft?> _showManualFlashcardDialog(
  BuildContext context, {
  required String selectedText,
}) async {
  final questionController = TextEditingController();
  final answerController = TextEditingController(text: selectedText);
  try {
    return await showDialog<_ManualFlashcardDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Criar flashcard'),
        content: SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width * 0.72,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Trecho selecionado', style: Theme.of(dialogContext).textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(child: SelectableText(selectedText)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: questionController,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Pergunta',
                    hintText: 'Digite a pergunta do flashcard',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answerController,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Resposta',
                    hintText: 'Edite a resposta livremente',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(
              _ManualFlashcardDraft(question: questionController.text, answer: answerController.text),
            ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar flashcard'),
          ),
        ],
      ),
    );
  } finally {
    questionController.dispose();
    answerController.dispose();
  }
}

class _SelectionNoteContent {
  const _SelectionNoteContent({
    required this.text,
    required this.sourceText,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontSize = 16,
    this.fontFamily = 'Roboto',
    this.textAlign = 'left',
  });

  static const prefix = 'lexpdf-note-v1:';
  final String text;
  final String sourceText;
  final bool bold;
  final bool italic;
  final bool underline;
  final double fontSize;
  final String fontFamily;
  final String textAlign;

  String encode() {
    final payload = jsonEncode({
      'text': text,
      'sourceText': sourceText,
      'bold': bold,
      'italic': italic,
      'underline': underline,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'textAlign': textAlign,
    });
    return '$prefix${base64Url.encode(utf8.encode(payload))}';
  }
}

Future<_SelectionNoteContent?> _showSelectionNoteEditor(
  BuildContext context, {
  required String selectedText,
}) async {
  final controller = TextEditingController();
  var bold = false;
  var italic = false;
  var underline = false;
  var fontSize = 16.0;
  var fontFamily = 'Roboto';
  var textAlign = 'left';

  try {
    return await showDialog<_SelectionNoteContent>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final align = switch (textAlign) {
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            'justify' => TextAlign.justify,
            _ => TextAlign.left,
          };
          final style = TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: underline ? TextDecoration.underline : TextDecoration.none,
          );
          return AlertDialog(
            title: const Text('Anotar trecho'),
            content: SizedBox(
              width: MediaQuery.sizeOf(dialogContext).width * 0.78,
              height: MediaQuery.sizeOf(dialogContext).height * 0.62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Trecho selecionado', style: Theme.of(dialogContext).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 90),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(child: SelectableText(selectedText)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(tooltip: 'Negrito', isSelected: bold, onPressed: () => setDialogState(() => bold = !bold), icon: const Icon(Icons.format_bold)),
                      IconButton(tooltip: 'Itálico', isSelected: italic, onPressed: () => setDialogState(() => italic = !italic), icon: const Icon(Icons.format_italic)),
                      IconButton(tooltip: 'Sublinhado', isSelected: underline, onPressed: () => setDialogState(() => underline = !underline), icon: const Icon(Icons.format_underline)),
                      DropdownButton<double>(
                        value: fontSize,
                        items: const [12, 14, 16, 18, 20, 24, 28, 32]
                            .map((value) => DropdownMenuItem<double>(value: value.toDouble(), child: Text('$value pt')))
                            .toList(),
                        onChanged: (value) { if (value != null) setDialogState(() => fontSize = value); },
                      ),
                      DropdownButton<String>(
                        value: fontFamily,
                        items: const [
                          DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
                          DropdownMenuItem(value: 'sans-serif', child: Text('Sans')),
                          DropdownMenuItem(value: 'serif', child: Text('Serif')),
                          DropdownMenuItem(value: 'monospace', child: Text('Monospace')),
                        ],
                        onChanged: (value) { if (value != null) setDialogState(() => fontFamily = value); },
                      ),
                      for (final option in const <(String, IconData)>[
                        ('left', Icons.format_align_left),
                        ('center', Icons.format_align_center),
                        ('right', Icons.format_align_right),
                        ('justify', Icons.format_align_justify),
                      ])
                        IconButton(
                          isSelected: textAlign == option.$1,
                          onPressed: () => setDialogState(() => textAlign = option.$1),
                          icon: Icon(option.$2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlign: align,
                      textAlignVertical: TextAlignVertical.top,
                      style: style,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Escreva sua anotação…',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _SelectionNoteContent(
                    text: controller.text.trim(),
                    sourceText: selectedText,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    fontSize: fontSize,
                    fontFamily: fontFamily,
                    textAlign: textAlign,
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar anotação'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    controller.dispose();
  }
}
