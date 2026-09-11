import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/annotations/pdf_annotation_object.dart';
import '../core/storage/local_pdf_annotation_object_store.dart';

class PdfStickyNoteOverlay extends StatefulWidget {
  const PdfStickyNoteOverlay({
    required this.documentId,
    required this.pageNumber,
    required this.store,
    required this.createEnabled,
    this.onNoteSaved,
    super.key,
  });

  final String documentId;
  final int pageNumber;
  final LocalPdfAnnotationObjectStore store;
  final bool createEnabled;
  final VoidCallback? onNoteSaved;

  @override
  State<PdfStickyNoteOverlay> createState() => _PdfStickyNoteOverlayState();
}

class _StickyNoteContent {
  const _StickyNoteContent({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontSize = 16,
  });

  static const prefix = 'lexpdf-note-v1:';

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final double fontSize;

  String encode() {
    final payload = jsonEncode({
      'text': text,
      'bold': bold,
      'italic': italic,
      'underline': underline,
      'fontSize': fontSize,
    });
    return '$prefix${base64Url.encode(utf8.encode(payload))}';
  }

  static _StickyNoteContent decode(String? value) {
    if (value == null || value.isEmpty) {
      return const _StickyNoteContent(text: '');
    }
    if (!value.startsWith(prefix)) return _StickyNoteContent(text: value);
    try {
      final raw = value.substring(prefix.length);
      final map = jsonDecode(utf8.decode(base64Url.decode(raw)))
          as Map<String, dynamic>;
      return _StickyNoteContent(
        text: map['text'] as String? ?? '',
        bold: map['bold'] as bool? ?? false,
        italic: map['italic'] as bool? ?? false,
        underline: map['underline'] as bool? ?? false,
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16,
      );
    } catch (_) {
      return _StickyNoteContent(text: value);
    }
  }
}

class _NoteEditorResult {
  const _NoteEditorResult.save(this.content) : delete = false;
  const _NoteEditorResult.delete()
      : content = null,
        delete = true;

  final _StickyNoteContent? content;
  final bool delete;
}

class _PdfStickyNoteOverlayState extends State<PdfStickyNoteOverlay> {
  static const _markerSize = 34.0;
  final List<PdfAnnotationObject> _notes = <PdfAnnotationObject>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant PdfStickyNoteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.pageNumber != widget.pageNumber) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final objects = await widget.store.listForPage(
      widget.documentId,
      widget.pageNumber,
    );
    if (!mounted) return;
    setState(() {
      _notes
        ..clear()
        ..addAll(
          objects.where((item) => item.type == PdfAnnotationObjectType.note),
        );
      _loading = false;
    });
  }

  Future<void> _createAt(Offset local, Size size) async {
    if (!widget.createEnabled || size.width <= 0 || size.height <= 0) return;
    final result = await _showEditor(
      initial: const _StickyNoteContent(text: ''),
    );
    if (result == null || result.delete || result.content == null) return;
    final value = result.content!;
    if (value.text.trim().isEmpty) return;

    final now = DateTime.now().toUtc();
    const normalizedSize = 0.055;
    final x = (local.dx / size.width).clamp(0.0, 1.0 - normalizedSize);
    final y = (local.dy / size.height).clamp(0.0, 1.0 - normalizedSize);
    final object = PdfAnnotationObject(
      id: 'pdf-note-${now.microsecondsSinceEpoch.toRadixString(36)}',
      documentId: widget.documentId,
      pageNumber: widget.pageNumber,
      type: PdfAnnotationObjectType.note,
      x: x,
      y: y,
      width: normalizedSize,
      height: normalizedSize,
      colorValue: 0xFF5D4A00,
      fillColorValue: 0xFFFFD54F,
      opacity: 1,
      strokeWidth: 1.5,
      textValue: value.encode(),
      createdAt: now,
      updatedAt: now,
    );
    await widget.store.upsert(object);
    if (!mounted) return;
    setState(() => _notes.add(object));
    widget.onNoteSaved?.call();
  }

  Future<void> _edit(PdfAnnotationObject object) async {
    final result = await _showEditor(
      initial: _StickyNoteContent.decode(object.textValue),
      existing: true,
    );
    if (result == null) return;
    if (result.delete) {
      await widget.store.delete(object.id);
      if (!mounted) return;
      setState(() => _notes.removeWhere((item) => item.id == object.id));
      return;
    }
    final content = result.content;
    if (content == null || content.text.trim().isEmpty) return;
    final updated = object.copyWith(textValue: content.encode());
    await widget.store.upsert(updated);
    if (!mounted) return;
    final index = _notes.indexWhere((item) => item.id == object.id);
    if (index >= 0) setState(() => _notes[index] = updated);
  }

  Future<_NoteEditorResult?> _showEditor({
    required _StickyNoteContent initial,
    bool existing = false,
  }) async {
    final controller = TextEditingController(text: initial.text);
    var bold = initial.bold;
    var italic = initial.italic;
    var underline = initial.underline;
    var fontSize = initial.fontSize.clamp(12.0, 32.0);
    final result = await showDialog<_NoteEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final style = TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration:
                underline ? TextDecoration.underline : TextDecoration.none,
          );
          return AlertDialog(
            title: Text(existing ? 'Editar anotação' : 'Nova anotação'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Negrito',
                        isSelected: bold,
                        onPressed: () => setDialogState(() => bold = !bold),
                        icon: const Icon(Icons.format_bold),
                      ),
                      IconButton(
                        tooltip: 'Itálico',
                        isSelected: italic,
                        onPressed: () => setDialogState(() => italic = !italic),
                        icon: const Icon(Icons.format_italic),
                      ),
                      IconButton(
                        tooltip: 'Sublinhado',
                        isSelected: underline,
                        onPressed: () =>
                            setDialogState(() => underline = !underline),
                        icon: const Icon(Icons.format_underline),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<double>(
                        value: <double>[12, 14, 16, 18, 20, 24, 28, 32]
                                .contains(fontSize)
                            ? fontSize
                            : 16,
                        tooltip: 'Tamanho da fonte',
                        items: const [
                          DropdownMenuItem(value: 12, child: Text('12 pt')),
                          DropdownMenuItem(value: 14, child: Text('14 pt')),
                          DropdownMenuItem(value: 16, child: Text('16 pt')),
                          DropdownMenuItem(value: 18, child: Text('18 pt')),
                          DropdownMenuItem(value: 20, child: Text('20 pt')),
                          DropdownMenuItem(value: 24, child: Text('24 pt')),
                          DropdownMenuItem(value: 28, child: Text('28 pt')),
                          DropdownMenuItem(value: 32, child: Text('32 pt')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => fontSize = value);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 6,
                    maxLines: 12,
                    style: style,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Escreva sua anotação…',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (existing)
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(const _NoteEditorResult.delete()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _NoteEditorResult.save(
                    _StickyNoteContent(
                      text: controller.text.trim(),
                      bold: bold,
                      italic: italic,
                      underline: underline,
                      fontSize: fontSize,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final maxLeft = (size.width - _markerSize).clamp(0.0, double.infinity);
        final maxTop = (size.height - _markerSize).clamp(0.0, double.infinity);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.createEnabled)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) =>
                      unawaited(_createAt(details.localPosition, size)),
                  child: const SizedBox.expand(),
                ),
              ),
            for (final note in _notes)
              Positioned(
                left: (note.x * size.width - _markerSize / 2)
                    .clamp(0.0, maxLeft),
                top: (note.y * size.height - _markerSize / 2)
                    .clamp(0.0, maxTop),
                width: _markerSize,
                height: _markerSize,
                child: Tooltip(
                  message: _StickyNoteContent.decode(note.textValue).text,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => unawaited(_edit(note)),
                      child: const Icon(
                        Icons.sticky_note_2,
                        color: Color(0xFFFFC107),
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            if (_loading)
              const Positioned(
                right: 4,
                bottom: 4,
                child: IgnorePointer(
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
