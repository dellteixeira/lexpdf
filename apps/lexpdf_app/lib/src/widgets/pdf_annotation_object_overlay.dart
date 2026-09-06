import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/annotations/pdf_annotation_object.dart';
import '../core/storage/local_pdf_annotation_object_store.dart';

class PdfAnnotationObjectOverlay extends StatefulWidget {
  const PdfAnnotationObjectOverlay({
    required this.documentId,
    required this.pageNumber,
    required this.store,
    required this.enabled,
    required this.colorValue,
    this.onChanged,
    super.key,
  });

  final String documentId;
  final int pageNumber;
  final LocalPdfAnnotationObjectStore store;
  final bool enabled;
  final int colorValue;
  final VoidCallback? onChanged;

  @override
  State<PdfAnnotationObjectOverlay> createState() =>
      _PdfAnnotationObjectOverlayState();
}

enum _AnnotationTool {
  select,
  note,
  text,
  line,
  arrow,
  rectangle,
  ellipse,
  stamp,
  signature,
}

class _PdfAnnotationObjectOverlayState
    extends State<PdfAnnotationObjectOverlay> {
  final List<PdfAnnotationObject> _objects = [];
  _AnnotationTool _tool = _AnnotationTool.select;
  String? _selectedId;
  Offset? _start;
  Offset? _current;
  PdfAnnotationObject? _dragOrigin;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant PdfAnnotationObjectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.pageNumber != widget.pageNumber) {
      _selectedId = null;
      unawaited(_reload());
    }
    if (oldWidget.enabled && !widget.enabled) {
      _selectedId = null;
      _start = null;
      _current = null;
      _dragOrigin = null;
    }
  }

  Future<void> _reload() async {
    final values = await widget.store.listForPage(
      widget.documentId,
      widget.pageNumber,
    );
    if (!mounted) return;
    setState(() {
      _objects
        ..clear()
        ..addAll(values);
      _loading = false;
    });
  }

  Offset _normalized(Offset local, Size size) => Offset(
        size.width <= 0 ? 0 : (local.dx / size.width).clamp(0.0, 1.0),
        size.height <= 0 ? 0 : (local.dy / size.height).clamp(0.0, 1.0),
      );

  void _down(PointerDownEvent event, Size size) {
    if (!widget.enabled) return;
    final point = _normalized(event.localPosition, size);
    _start = point;
    _current = point;
    if (_tool == _AnnotationTool.select) {
      PdfAnnotationObject? hit;
      for (final object in _objects.reversed) {
        if (_contains(object, point)) {
          hit = object;
          break;
        }
      }
      setState(() {
        _selectedId = hit?.id;
        _dragOrigin = hit;
      });
      return;
    }
    setState(() {});
  }

  void _move(PointerMoveEvent event, Size size) {
    if (!widget.enabled || _start == null) return;
    final point = _normalized(event.localPosition, size);
    _current = point;
    if (_tool == _AnnotationTool.select && _dragOrigin != null) {
      final delta = point - _start!;
      final origin = _dragOrigin!;
      final moved = origin.copyWith(
        x: (origin.x + delta.dx).clamp(0.0, 1.0 - origin.width),
        y: (origin.y + delta.dy).clamp(0.0, 1.0 - origin.height),
      );
      final index = _objects.indexWhere((value) => value.id == origin.id);
      if (index >= 0) _objects[index] = moved;
    }
    setState(() {});
  }

  void _up(PointerUpEvent event, Size size) {
    if (!widget.enabled || _start == null) return;
    final end = _normalized(event.localPosition, size);
    _current = end;
    if (_tool == _AnnotationTool.select) {
      final selected = _selectedObject;
      _resetGesture();
      if (selected != null && _dragOrigin != null) {
        unawaited(widget.store.upsert(selected));
        widget.onChanged?.call();
      }
      _dragOrigin = null;
      return;
    }

    final tool = _tool;
    final start = _start!;
    _resetGesture();
    if (_isTextual(tool)) {
      unawaited(_createTextual(tool, start));
    } else {
      unawaited(_createShape(tool, start, end));
    }
  }

  void _cancel(PointerCancelEvent event) {
    _resetGesture();
    _dragOrigin = null;
  }

  void _resetGesture() {
    _start = null;
    _current = null;
    if (mounted) setState(() {});
  }

  bool _contains(PdfAnnotationObject object, Offset point) {
    const padding = 0.012;
    final left = object.x - padding;
    final top = object.y - padding;
    final right = object.x + object.width + padding;
    final bottom = object.y + object.height + padding;
    return point.dx >= left &&
        point.dx <= right &&
        point.dy >= top &&
        point.dy <= bottom;
  }

  bool _isTextual(_AnnotationTool tool) => switch (tool) {
        _AnnotationTool.note ||
        _AnnotationTool.text ||
        _AnnotationTool.stamp ||
        _AnnotationTool.signature => true,
        _ => false,
      };

  Future<void> _createTextual(_AnnotationTool tool, Offset point) async {
    String? text;
    if (tool == _AnnotationTool.stamp) {
      text = 'APROVADO';
    } else {
      text = await _askText(
        title: switch (tool) {
          _AnnotationTool.note => 'Nova nota',
          _AnnotationTool.text => 'Caixa de texto',
          _AnnotationTool.signature => 'Assinatura textual',
          _ => 'Texto',
        },
        hint: switch (tool) {
          _AnnotationTool.note => 'Digite o comentário',
          _AnnotationTool.signature => 'Digite o nome a assinar',
          _ => 'Digite o texto',
        },
      );
      if (text == null || text.trim().isEmpty) return;
    }

    final type = switch (tool) {
      _AnnotationTool.note => PdfAnnotationObjectType.note,
      _AnnotationTool.text => PdfAnnotationObjectType.text,
      _AnnotationTool.stamp => PdfAnnotationObjectType.stamp,
      _AnnotationTool.signature => PdfAnnotationObjectType.signature,
      _ => throw StateError('Not a textual tool'),
    };
    final size = switch (type) {
      PdfAnnotationObjectType.note => const Size(0.24, 0.13),
      PdfAnnotationObjectType.text => const Size(0.30, 0.10),
      PdfAnnotationObjectType.stamp => const Size(0.22, 0.08),
      PdfAnnotationObjectType.signature => const Size(0.30, 0.09),
      _ => const Size(0.2, 0.1),
    };
    final now = DateTime.now().toUtc();
    final object = PdfAnnotationObject(
      id: 'pdf-annotation-${now.microsecondsSinceEpoch.toRadixString(36)}',
      documentId: widget.documentId,
      pageNumber: widget.pageNumber,
      type: type,
      x: point.dx.clamp(0.0, 1.0 - size.width),
      y: point.dy.clamp(0.0, 1.0 - size.height),
      width: size.width,
      height: size.height,
      colorValue: widget.colorValue,
      fillColorValue:
          type == PdfAnnotationObjectType.note ? 0xFFFFF59D : null,
      opacity: 1,
      strokeWidth: 2,
      textValue: text.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await widget.store.upsert(object);
    if (!mounted) return;
    setState(() {
      _objects.add(object);
      _selectedId = object.id;
      _tool = _AnnotationTool.select;
    });
    widget.onChanged?.call();
  }

  Future<void> _createShape(
    _AnnotationTool tool,
    Offset start,
    Offset end,
  ) async {
    final left = math.min(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final width = math.max((start.dx - end.dx).abs(), 0.01);
    final height = math.max((start.dy - end.dy).abs(), 0.01);
    final type = switch (tool) {
      _AnnotationTool.line => PdfAnnotationObjectType.line,
      _AnnotationTool.arrow => PdfAnnotationObjectType.arrow,
      _AnnotationTool.rectangle => PdfAnnotationObjectType.rectangle,
      _AnnotationTool.ellipse => PdfAnnotationObjectType.ellipse,
      _ => throw StateError('Not a shape tool'),
    };
    final now = DateTime.now().toUtc();
    final object = PdfAnnotationObject(
      id: 'pdf-annotation-${now.microsecondsSinceEpoch.toRadixString(36)}',
      documentId: widget.documentId,
      pageNumber: widget.pageNumber,
      type: type,
      x: left.clamp(0.0, 0.99),
      y: top.clamp(0.0, 0.99),
      width: math.min(width, 1 - left),
      height: math.min(height, 1 - top),
      colorValue: widget.colorValue,
      opacity: 1,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    );
    await widget.store.upsert(object);
    if (!mounted) return;
    setState(() {
      _objects.add(object);
      _selectedId = object.id;
      _tool = _AnnotationTool.select;
    });
    widget.onChanged?.call();
  }

  Future<String?> _askText({required String title, required String hint}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  PdfAnnotationObject? get _selectedObject {
    final id = _selectedId;
    if (id == null) return null;
    for (final object in _objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  Future<void> _deleteSelected() async {
    final object = _selectedObject;
    if (object == null) return;
    await widget.store.delete(object.id);
    if (!mounted) return;
    setState(() {
      _objects.removeWhere((value) => value.id == object.id);
      _selectedId = null;
    });
    widget.onChanged?.call();
  }

  Future<void> _updateSelected({double? strokeDelta, bool recolor = false}) async {
    final object = _selectedObject;
    if (object == null) return;
    final updated = object.copyWith(
      colorValue: recolor ? widget.colorValue : object.colorValue,
      strokeWidth: strokeDelta == null
          ? object.strokeWidth
          : (object.strokeWidth + strokeDelta).clamp(0.5, 20),
    );
    await widget.store.upsert(updated);
    final index = _objects.indexWhere((value) => value.id == object.id);
    if (!mounted || index < 0) return;
    setState(() => _objects[index] = updated);
    widget.onChanged?.call();
  }

  Future<void> _editSelectedText() async {
    final object = _selectedObject;
    if (object == null || object.textValue == null) return;
    final controller = TextEditingController(text: object.textValue);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar anotação'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final updated = object.copyWith(textValue: text.trim());
    await widget.store.upsert(updated);
    final index = _objects.indexWhere((value) => value.id == object.id);
    if (!mounted || index < 0) return;
    setState(() => _objects[index] = updated);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final selected = _selectedObject;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: _PdfAnnotationPainter(
                  objects: _objects,
                  selectedId: _selectedId,
                  previewTool: _tool,
                  start: _start,
                  current: _current,
                  previewColor: Color(widget.colorValue),
                ),
              ),
            ),
            if (widget.enabled)
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => _down(event, size),
                onPointerMove: (event) => _move(event, size),
                onPointerUp: (event) => _up(event, size),
                onPointerCancel: _cancel,
                child: const SizedBox.expand(),
              ),
            if (widget.enabled)
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                child: _Toolbar(
                  tool: _tool,
                  onTool: (tool) => setState(() {
                    _tool = tool;
                    if (tool != _AnnotationTool.select) _selectedId = null;
                  }),
                ),
              ),
            if (widget.enabled && selected != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Card(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected.textValue != null)
                        IconButton(
                          tooltip: 'Editar texto',
                          onPressed: _editSelectedText,
                          icon: const Icon(Icons.edit_note),
                        ),
                      IconButton(
                        tooltip: 'Aplicar cor atual',
                        onPressed: () => _updateSelected(recolor: true),
                        icon: const Icon(Icons.palette_outlined),
                      ),
                      IconButton(
                        tooltip: 'Diminuir espessura',
                        onPressed: () => _updateSelected(strokeDelta: -0.5),
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: 'Aumentar espessura',
                        onPressed: () => _updateSelected(strokeDelta: 0.5),
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tool, required this.onTool});
  final _AnnotationTool tool;
  final ValueChanged<_AnnotationTool> onTool;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _button(_AnnotationTool.select, Icons.pan_tool_alt_outlined, 'Selecionar'),
            _button(_AnnotationTool.note, Icons.sticky_note_2_outlined, 'Nota'),
            _button(_AnnotationTool.text, Icons.text_fields, 'Texto'),
            _button(_AnnotationTool.line, Icons.horizontal_rule, 'Linha'),
            _button(_AnnotationTool.arrow, Icons.arrow_right_alt, 'Seta'),
            _button(_AnnotationTool.rectangle, Icons.crop_square, 'Retângulo'),
            _button(_AnnotationTool.ellipse, Icons.circle_outlined, 'Elipse'),
            _button(_AnnotationTool.stamp, Icons.approval_outlined, 'Carimbo'),
            _button(_AnnotationTool.signature, Icons.draw_outlined, 'Assinatura'),
          ],
        ),
      ),
    );
  }

  Widget _button(_AnnotationTool value, IconData icon, String tooltip) {
    return IconButton(
      tooltip: tooltip,
      isSelected: tool == value,
      onPressed: () => onTool(value),
      icon: Icon(icon),
    );
  }
}

class _PdfAnnotationPainter extends CustomPainter {
  const _PdfAnnotationPainter({
    required this.objects,
    required this.selectedId,
    required this.previewTool,
    required this.start,
    required this.current,
    required this.previewColor,
  });

  final List<PdfAnnotationObject> objects;
  final String? selectedId;
  final _AnnotationTool previewTool;
  final Offset? start;
  final Offset? current;
  final Color previewColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final object in objects) {
      _paintObject(canvas, size, object);
      if (object.id == selectedId) {
        final rect = Rect.fromLTWH(
          object.x * size.width,
          object.y * size.height,
          object.width * size.width,
          object.height * size.height,
        );
        canvas.drawRect(
          rect.inflate(3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.blueAccent,
        );
      }
    }

    if (start != null && current != null &&
        previewTool != _AnnotationTool.select &&
        previewTool != _AnnotationTool.note &&
        previewTool != _AnnotationTool.text &&
        previewTool != _AnnotationTool.stamp &&
        previewTool != _AnnotationTool.signature) {
      final a = Offset(start!.dx * size.width, start!.dy * size.height);
      final b = Offset(current!.dx * size.width, current!.dy * size.height);
      final rect = Rect.fromPoints(a, b);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = previewColor.withValues(alpha: 0.75);
      switch (previewTool) {
        case _AnnotationTool.line:
          canvas.drawLine(a, b, paint);
        case _AnnotationTool.arrow:
          _drawArrow(canvas, a, b, paint);
        case _AnnotationTool.rectangle:
          canvas.drawRect(rect, paint);
        case _AnnotationTool.ellipse:
          canvas.drawOval(rect, paint);
        default:
          break;
      }
    }
  }

  void _paintObject(Canvas canvas, Size size, PdfAnnotationObject object) {
    final rect = Rect.fromLTWH(
      object.x * size.width,
      object.y * size.height,
      object.width * size.width,
      object.height * size.height,
    );
    final color = Color(object.colorValue).withValues(alpha: object.opacity);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = object.strokeWidth
      ..color = color;

    canvas.save();
    if (object.rotation != 0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(object.rotation);
      canvas.translate(-rect.center.dx, -rect.center.dy);
    }
    switch (object.type) {
      case PdfAnnotationObjectType.line:
        canvas.drawLine(rect.topLeft, rect.bottomRight, paint);
      case PdfAnnotationObjectType.arrow:
        _drawArrow(canvas, rect.topLeft, rect.bottomRight, paint);
      case PdfAnnotationObjectType.rectangle:
        _fillIfNeeded(canvas, rect, object);
        canvas.drawRect(rect, paint);
      case PdfAnnotationObjectType.ellipse:
        _fillIfNeeded(canvas, rect, object);
        canvas.drawOval(rect, paint);
      case PdfAnnotationObjectType.note:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = Color(object.fillColorValue ?? 0xFFFFF59D)
                .withValues(alpha: object.opacity),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          paint,
        );
        _drawText(canvas, rect.deflate(6), object.textValue ?? '', color,
            fontSize: 12);
      case PdfAnnotationObjectType.text:
        _drawText(canvas, rect, object.textValue ?? '', color, fontSize: 14);
      case PdfAnnotationObjectType.stamp:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          paint..strokeWidth = math.max(2.0, object.strokeWidth),
        );
        _drawText(
          canvas,
          rect.deflate(4),
          (object.textValue ?? 'APROVADO').toUpperCase(),
          color,
          fontSize: 13,
          bold: true,
          centered: true,
        );
      case PdfAnnotationObjectType.signature:
        _drawText(
          canvas,
          rect,
          object.textValue ?? '',
          color,
          fontSize: 18,
          italic: true,
          centered: true,
        );
    }
    canvas.restore();
  }

  void _fillIfNeeded(Canvas canvas, Rect rect, PdfAnnotationObject object) {
    final value = object.fillColorValue;
    if (value == null) return;
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color(value).withValues(alpha: object.opacity * 0.2),
    );
  }

  void _drawText(
    Canvas canvas,
    Rect rect,
    String text,
    Color color, {
    required double fontSize,
    bool bold = false,
    bool italic = false,
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: centered ? TextAlign.center : TextAlign.left,
      maxLines: 5,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0.0, rect.width));
    final dx = centered ? rect.left + (rect.width - painter.width) / 2 : rect.left;
    final dy = centered ? rect.top + (rect.height - painter.height) / 2 : rect.top;
    painter.paint(canvas, Offset(dx, dy));
  }

  static void _drawArrow(Canvas canvas, Offset a, Offset b, Paint paint) {
    canvas.drawLine(a, b, paint);
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final length = math.max(8.0, paint.strokeWidth * 4);
    const spread = 0.55;
    final p1 = b - Offset(
      math.cos(angle - spread) * length,
      math.sin(angle - spread) * length,
    );
    final p2 = b - Offset(
      math.cos(angle + spread) * length,
      math.sin(angle + spread) * length,
    );
    canvas.drawLine(b, p1, paint);
    canvas.drawLine(b, p2, paint);
  }

  @override
  bool shouldRepaint(covariant _PdfAnnotationPainter oldDelegate) => true;
}
