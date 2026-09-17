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
    this.fontFamily = 'Roboto',
    this.textAlign = 'left',
  });

  static const prefix = 'lexpdf-note-v1:';

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final double fontSize;
  final String fontFamily;
  final String textAlign;

  String encode() {
    final payload = jsonEncode({
      'text': text,
      'bold': bold,
      'italic': italic,
      'underline': underline,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'textAlign': textAlign,
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
        fontFamily: map['fontFamily'] as String? ?? 'Roboto',
        textAlign: map['textAlign'] as String? ?? 'left',
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

class _StickyNoteDragData {
  const _StickyNoteDragData({
    required this.object,
    required this.onPersistedMove,
  });

  final PdfAnnotationObject object;
  final ValueChanged<PdfAnnotationObject> onPersistedMove;
}

class _PdfStickyNoteOverlayState extends State<PdfStickyNoteOverlay> {
  static const _markerSize = 26.0;
  static const _autoScrollEdge = 56.0;
  static const _autoScrollStep = 120.0;
  final GlobalKey _dropSurfaceKey = GlobalKey();
  final List<PdfAnnotationObject> _notes = <PdfAnnotationObject>[];
  bool _loading = true;
  bool _dropActive = false;
  DateTime _lastAutoScrollAt = DateTime.fromMillisecondsSinceEpoch(0);

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

  Future<void> _acceptDrop(
    DragTargetDetails<_StickyNoteDragData> details,
    Size size,
  ) async {
    if (size.width <= 0 || size.height <= 0) return;
    final renderObject = _dropSurfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(details.offset);
    final source = details.data.object;
    final x = (local.dx / size.width).clamp(0.0, 1.0 - source.width);
    final y = (local.dy / size.height).clamp(0.0, 1.0 - source.height);
    final moved = source.copyWith(
      pageNumber: widget.pageNumber,
      x: x,
      y: y,
      updatedAt: DateTime.now().toUtc(),
    );
    await widget.store.upsert(moved);
    if (!mounted) return;
    setState(() {
      _dropActive = false;
      _notes.removeWhere((item) => item.id == moved.id);
      _notes.add(moved);
    });
    details.data.onPersistedMove(moved);
  }

  void _sourceNoteMoved(PdfAnnotationObject moved) {
    if (!mounted) return;
    setState(() {
      final index = _notes.indexWhere((item) => item.id == moved.id);
      if (moved.pageNumber != widget.pageNumber) {
        if (index >= 0) _notes.removeAt(index);
      } else if (index >= 0) {
        _notes[index] = moved;
      } else {
        _notes.add(moved);
      }
    });
  }

  void _maybeAutoScroll(Offset globalPosition) {
    final renderObject = _dropSurfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(globalPosition);
    final now = DateTime.now();
    if (now.difference(_lastAutoScrollAt) < const Duration(milliseconds: 90)) {
      return;
    }
    double? delta;
    if (local.dy <= _autoScrollEdge) {
      delta = -_autoScrollStep;
    } else if (local.dy >= renderObject.size.height - _autoScrollEdge) {
      delta = _autoScrollStep;
    }
    if (delta == null) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.position.hasPixels) return;
    _lastAutoScrollAt = now;
    final target = (scrollable.position.pixels + delta).clamp(
      scrollable.position.minScrollExtent,
      scrollable.position.maxScrollExtent,
    );
    unawaited(
      scrollable.position.animateTo(
        target,
        duration: const Duration(milliseconds: 90),
        curve: Curves.linear,
      ),
    );
  }

  Widget _markerIcon({double opacity = 1}) => Opacity(
        opacity: opacity,
        child: const Material(
          color: Colors.transparent,
          child: Icon(
            Icons.push_pin_rounded,
            color: Color(0xFFFFB300),
            size: 20,
          ),
        ),
      );

  Future<_NoteEditorResult?> _showEditor({
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final maxLeft = (size.width - _markerSize).clamp(0.0, double.infinity);
        final maxTop = (size.height - _markerSize).clamp(0.0, double.infinity);
        return DragTarget<_StickyNoteDragData>(
          key: _dropSurfaceKey,
          onWillAcceptWithDetails: (details) =>
              details.data.object.documentId == widget.documentId,
          onMove: (details) {
            if (!_dropActive && mounted) setState(() => _dropActive = true);
            _maybeAutoScroll(details.offset);
          },
          onLeave: (_) {
            if (_dropActive && mounted) setState(() => _dropActive = false);
          },
          onAcceptWithDetails: (details) => unawaited(_acceptDrop(details, size)),
          builder: (context, candidateData, rejectedData) => Stack(
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
              if (_dropActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
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
                    message:
                        '${_StickyNoteContent.decode(note.textValue).text}\nSegure e arraste para mover',
                    child: LongPressDraggable<_StickyNoteDragData>(
                      data: _StickyNoteDragData(
                        object: note,
                        onPersistedMove: _sourceNoteMoved,
                      ),
                      delay: const Duration(milliseconds: 280),
                      hapticFeedbackOnStart: true,
                      feedback: Material(
                        color: Colors.transparent,
                        elevation: 6,
                        child: SizedBox.square(
                          dimension: _markerSize,
                          child: _markerIcon(),
                        ),
                      ),
                      childWhenDragging: _markerIcon(opacity: 0.28),
                      onDragUpdate: (details) =>
                          _maybeAutoScroll(details.globalPosition),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => unawaited(_edit(note)),
                          child: _markerIcon(),
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
          ),
        );
      },
    );
  }
}
