from pathlib import Path

ROOT = Path('apps/lexpdf_app')


def read(rel):
    return (ROOT / rel).read_text()


def write(rel, text):
    (ROOT / rel).write_text(text)


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'missing expected fragment: {label}')
    return text.replace(old, new, 1)


def replace_between(text, start_marker, end_marker, replacement, label):
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'missing start marker: {label}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'missing end marker: {label}')
    return text[:start] + replacement + text[end:]


rel = 'lib/src/widgets/pdf_selection_action_menu.dart'
text = read(rel)
text = replace_once(text, "import 'dart:async';\n", "import 'dart:async';\nimport 'dart:convert';\n", 'dart:convert import')
text = text.replace("import '../screens/ai_study_screen.dart';\n", '')

old_flash = """      ContextMenuButtonItem(\n        label: 'Flashcard',\n        onPressed: () {\n          params.dismissContextMenu();\n          unawaited(\n            _runStudyAction(context, delegate, AiStudyAction.flashcards),\n          );\n        },\n      ),\n"""
new_flash = """      ContextMenuButtonItem(\n        label: 'Flashcard',\n        onPressed: () {\n          params.dismissContextMenu();\n          unawaited(_createManualFlashcard(context, delegate));\n        },\n      ),\n"""
text = replace_once(text, old_flash, new_flash, 'manual flashcard action')

for label, action in [('Questão', 'questions'), ('Explicar', 'explain')]:
    block = f"""      ContextMenuButtonItem(\n        label: '{label}',\n        onPressed: () {{\n          params.dismissContextMenu();\n          unawaited(\n            _runStudyAction(context, delegate, AiStudyAction.{action}),\n          );\n        }},\n      ),\n"""
    if block not in text:
        raise SystemExit(f'missing action block: {label}')
    text = text.replace(block, '', 1)

manual_method = r'''  Future<void> _createManualFlashcard(
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

'''
text = replace_between(text, '  Future<void> _runStudyAction(', '  Future<void> _createNoteFromSelection(', manual_method, 'manual flashcard method')

note_method = r'''  Future<void> _createNoteFromSelection(
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

'''
text = replace_between(text, '  Future<void> _createNoteFromSelection(', '  String _selectionText(', note_method, 'rich note method')

helpers = r'''

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
'''
text = text.rstrip() + helpers + '\n'
write(rel, text)

rel = 'lib/src/widgets/pdf_sticky_note_overlay.dart'
text = read(rel)
text = replace_once(text, """    this.underline = false,\n    this.fontSize = 16,\n  });\n""", """    this.underline = false,\n    this.fontSize = 16,\n    this.fontFamily = 'Roboto',\n    this.textAlign = 'left',\n  });\n""", 'sticky constructor')
text = replace_once(text, """  final bool underline;\n  final double fontSize;\n""", """  final bool underline;\n  final double fontSize;\n  final String fontFamily;\n  final String textAlign;\n""", 'sticky fields')
text = replace_once(text, """      'underline': underline,\n      'fontSize': fontSize,\n""", """      'underline': underline,\n      'fontSize': fontSize,\n      'fontFamily': fontFamily,\n      'textAlign': textAlign,\n""", 'sticky encode')
text = replace_once(text, """        underline: map['underline'] as bool? ?? false,\n        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16,\n""", """        underline: map['underline'] as bool? ?? false,\n        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16,\n        fontFamily: map['fontFamily'] as String? ?? 'Roboto',\n        textAlign: map['textAlign'] as String? ?? 'left',\n""", 'sticky decode')
text = replace_once(text, '  static const _markerSize = 34.0;', '  static const _markerSize = 26.0;', 'marker size')
text = replace_once(text, """  Widget _markerIcon({double opacity = 1}) => Opacity(\n        opacity: opacity,\n        child: const Material(\n          color: Colors.transparent,\n          child: Icon(\n            Icons.sticky_note_2,\n            color: Color(0xFFFFC107),\n            size: 30,\n          ),\n        ),\n      );\n""", """  Widget _markerIcon({double opacity = 1}) => Opacity(\n        opacity: opacity,\n        child: const Material(\n          color: Colors.transparent,\n          child: Icon(\n            Icons.push_pin_rounded,\n            color: Color(0xFFFFB300),\n            size: 20,\n          ),\n        ),\n      );\n""", 'pin icon')

new_editor = r'''  Future<_NoteEditorResult?> _showEditor({
    required _StickyNoteContent initial,
    bool existing = false,
  }) async {
    final controller = TextEditingController(text: initial.text);
    var bold = initial.bold;
    var italic = initial.italic;
    var underline = initial.underline;
    var fontSize = initial.fontSize.clamp(12.0, 32.0);
    var fontFamily = initial.fontFamily;
    var textAlign = initial.textAlign;
    final result = await showDialog<_NoteEditorResult>(
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
            title: Text(existing ? 'Editar anotação' : 'Nova anotação'),
            content: SizedBox(
              width: MediaQuery.sizeOf(dialogContext).width * 0.78,
              height: MediaQuery.sizeOf(dialogContext).height * 0.58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                        value: const ['Roboto', 'sans-serif', 'serif', 'monospace'].contains(fontFamily) ? fontFamily : 'Roboto',
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
              if (existing)
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(const _NoteEditorResult.delete()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir'),
                ),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _NoteEditorResult.save(
                    _StickyNoteContent(
                      text: controller.text.trim(),
                      bold: bold,
                      italic: italic,
                      underline: underline,
                      fontSize: fontSize,
                      fontFamily: fontFamily,
                      textAlign: textAlign,
                    ),
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

'''
text = replace_between(text, '  Future<_NoteEditorResult?> _showEditor({', '  @override\n  Widget build(BuildContext context) {', new_editor, 'sticky editor')
write(rel, text)

rel = 'lib/src/screens/pdf_workspace_stylus_screen.dart'
text = read(rel)
text = replace_once(text, """    onChanged: () {\n      if (!mounted) return;\n      setState(() {});\n      _controller.invalidate();\n    },\n""", """    onChanged: () {\n      if (!mounted) return;\n      setState(() => _annotationRevision++);\n      _controller.invalidate();\n    },\n""", 'annotation callback')
text = replace_once(text, '  int _inkCount = 0;\n', '  int _inkCount = 0;\n  int _annotationRevision = 0;\n', 'annotation revision')
text = replace_once(text, "'sticky-${page.pageNumber}-${_stylusMode.name}',", "'sticky-${page.pageNumber}-${_stylusMode.name}-$_annotationRevision',", 'sticky key')
write(rel, text)

(ROOT / 'test/manual_flashcard_rich_note_contract_test.dart').write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection study flow is manual and omits question/explain actions', () {
    final source = File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();
    expect(source, contains("label: 'Flashcard'"));
    expect(source, contains('_createManualFlashcard(context, delegate)'));
    expect(source, contains("labelText: 'Pergunta'"));
    expect(source, contains("labelText: 'Resposta'"));
    expect(source, isNot(contains("label: 'Questão'")));
    expect(source, isNot(contains("label: 'Explicar'")));
  });

  test('selection notes are anchored rich-text pins', () {
    final menu = File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();
    final overlay = File('lib/src/widgets/pdf_sticky_note_overlay.dart').readAsStringSync();
    expect(menu, contains('enumerateFragmentBoundingRects()'));
    expect(menu, contains("'fontFamily': fontFamily"));
    expect(menu, contains("'textAlign': textAlign"));
    expect(menu, contains('Icons.format_bold'));
    expect(menu, contains('Icons.format_italic'));
    expect(menu, contains('Icons.format_underline'));
    expect(overlay, contains('Icons.push_pin_rounded'));
    expect(overlay, contains('static const _markerSize = 26.0'));
    expect(overlay, contains("fontFamily: map['fontFamily']"));
  });
}
''')

print('manual flashcards + rich anchored notes codemod applied')
