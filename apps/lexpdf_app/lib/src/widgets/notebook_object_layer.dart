import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/notebook/notebook_object_models.dart';

enum _ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

TextAlign _notebookFlutterTextAlign(NotebookTextAlign value) => switch (value) {
  NotebookTextAlign.left => TextAlign.left,
  NotebookTextAlign.center => TextAlign.center,
  NotebookTextAlign.right => TextAlign.right,
  NotebookTextAlign.justify => TextAlign.justify,
};

class NotebookObjectLayer extends StatefulWidget {
  const NotebookObjectLayer({
    required this.objects,
    required this.enabled,
    required this.onObjectChanged,
    required this.onSelectionChanged,
    this.onObjectDoubleTap,
    this.editingTextId,
    this.onTextChanged,
    this.onTextEditingComplete,
    this.onEmptyTap,
    this.selectedId,
    super.key,
  });

  final List<NotebookObject> objects;
  final bool enabled;
  final String? selectedId;
  final ValueChanged<NotebookObject> onObjectChanged;
  final ValueChanged<String?> onSelectionChanged;
  final ValueChanged<NotebookObject>? onObjectDoubleTap;
  final String? editingTextId;
  final ValueChanged<NotebookObject>? onTextChanged;
  final ValueChanged<NotebookObject>? onTextEditingComplete;
  final VoidCallback? onEmptyTap;

  @override
  State<NotebookObjectLayer> createState() => _NotebookObjectLayerState();
}

class _NotebookObjectLayerState extends State<NotebookObjectLayer> {
  static const double _minimumObjectExtent = 24;
  static const double _handleExtent = 18;

  NotebookObject? _working;

  NotebookObject _effective(NotebookObject object) =>
      _working?.id == object.id ? _working! : object;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              widget.onSelectionChanged(null);
              widget.onEmptyTap?.call();
            },
          ),
          for (final raw in widget.objects)
            _buildObject(_effective(raw), widget.selectedId == raw.id),
        ],
      ),
    );
  }

  Widget _buildObject(NotebookObject object, bool selected) {
    final width = math.max(_minimumObjectExtent, object.width);
    final height = math.max(_minimumObjectExtent, object.height);
    final editingText =
        object.type == NotebookObjectType.text &&
        widget.editingTextId == object.id;

    return Positioned(
      left: object.x,
      top: object.y,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: object.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: editingText
                    ? SystemMouseCursors.text
                    : SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (_) => widget.onSelectionChanged(object.id),
                  onTap: () => widget.onSelectionChanged(object.id),
                  onDoubleTap: () {
                    widget.onSelectionChanged(object.id);
                    widget.onObjectDoubleTap?.call(object);
                  },
                  onPanStart: editingText
                      ? null
                      : (_) {
                          widget.onSelectionChanged(object.id);
                          _working = object;
                        },
                  onPanUpdate: editingText
                      ? null
                      : (details) {
                          final current = _working ?? object;
                          setState(() {
                            _working = current.copyWith(
                              x: current.x + details.delta.dx,
                              y: current.y + details.delta.dy,
                              updatedAt: DateTime.now().toUtc(),
                            );
                          });
                        },
                  onPanEnd: editingText ? null : (_) => _commitWorking(),
                  onPanCancel: editingText ? null : _cancelWorking,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (editingText)
                        _InlineNotebookTextEditor(
                          object: object,
                          onChanged: widget.onTextChanged,
                          onEditingComplete: widget.onTextEditingComplete,
                        )
                      else
                        _ObjectVisual(object: object),
                      if (selected && widget.editingTextId != object.id)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.7,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (selected && !editingText) ...[
              _buildResizeHandle(object, _ResizeHandle.topLeft),
              _buildResizeHandle(object, _ResizeHandle.topRight),
              _buildResizeHandle(object, _ResizeHandle.bottomLeft),
              _buildResizeHandle(object, _ResizeHandle.bottomRight),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResizeHandle(NotebookObject object, _ResizeHandle handle) {
    final left = switch (handle) {
      _ResizeHandle.topLeft || _ResizeHandle.bottomLeft => -_handleExtent / 2,
      _ResizeHandle.topRight || _ResizeHandle.bottomRight => null,
    };
    final right = switch (handle) {
      _ResizeHandle.topRight || _ResizeHandle.bottomRight => -_handleExtent / 2,
      _ResizeHandle.topLeft || _ResizeHandle.bottomLeft => null,
    };
    final top = switch (handle) {
      _ResizeHandle.topLeft || _ResizeHandle.topRight => -_handleExtent / 2,
      _ResizeHandle.bottomLeft || _ResizeHandle.bottomRight => null,
    };
    final bottom = switch (handle) {
      _ResizeHandle.bottomLeft ||
      _ResizeHandle.bottomRight => -_handleExtent / 2,
      _ResizeHandle.topLeft || _ResizeHandle.topRight => null,
    };
    final cursor = switch (handle) {
      _ResizeHandle.topLeft ||
      _ResizeHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      _ResizeHandle.topRight ||
      _ResizeHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    };

    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            widget.onSelectionChanged(object.id);
            _working = object;
          },
          onPanUpdate: (details) {
            final current = _working ?? object;
            setState(() {
              _working = _resize(current, handle, details.delta);
            });
          },
          onPanEnd: (_) => _commitWorking(),
          onPanCancel: _cancelWorking,
          child: Container(
            width: _handleExtent,
            height: _handleExtent,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.onPrimary,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  NotebookObject _resize(
    NotebookObject current,
    _ResizeHandle handle,
    Offset delta,
  ) {
    var x = current.x;
    var y = current.y;
    var width = current.width;
    var height = current.height;

    final resizeLeft =
        handle == _ResizeHandle.topLeft || handle == _ResizeHandle.bottomLeft;
    final resizeTop =
        handle == _ResizeHandle.topLeft || handle == _ResizeHandle.topRight;

    if (resizeLeft) {
      final nextWidth = math.max(_minimumObjectExtent, width - delta.dx);
      x += width - nextWidth;
      width = nextWidth;
    } else {
      width = math.max(_minimumObjectExtent, width + delta.dx);
    }

    if (resizeTop) {
      final nextHeight = math.max(_minimumObjectExtent, height - delta.dy);
      y += height - nextHeight;
      height = nextHeight;
    } else {
      height = math.max(_minimumObjectExtent, height + delta.dy);
    }

    return current.copyWith(
      x: x,
      y: y,
      width: width,
      height: height,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _commitWorking() {
    final next = _working;
    _working = null;
    if (next != null) widget.onObjectChanged(next);
    if (mounted) setState(() {});
  }

  void _cancelWorking() {
    _working = null;
    if (mounted) setState(() {});
  }
}

class _ObjectVisual extends StatelessWidget {
  const _ObjectVisual({required this.object});

  final NotebookObject object;

  @override
  Widget build(BuildContext context) {
    if (object.type == NotebookObjectType.text) {
      return SizedBox.expand(
        child: Text(
          object.textValue ?? '',
          maxLines: null,
          textAlign: _notebookFlutterTextAlign(object.textAlign),
          style: TextStyle(
            color: Color(object.colorValue),
            fontSize: object.fontSize ?? 12,
            fontFamily: object.fontFamily ?? 'Arial',
            fontWeight: object.fontBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: object.fontItalic ? FontStyle.italic : FontStyle.normal,
            decoration: object.fontUnderline ? TextDecoration.underline : null,
          ),
        ),
      );
    }
    if (object.type == NotebookObjectType.image) {
      final path = object.imagePath;
      if (path == null || path.isEmpty) return const SizedBox.expand();
      return ClipRect(
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }
    return CustomPaint(
      painter: _NotebookShapePainter(object),
      child: const SizedBox.expand(),
    );
  }
}

class _InlineNotebookTextEditor extends StatefulWidget {
  const _InlineNotebookTextEditor({
    required this.object,
    this.onChanged,
    this.onEditingComplete,
  });

  final NotebookObject object;
  final ValueChanged<NotebookObject>? onChanged;
  final ValueChanged<NotebookObject>? onEditingComplete;

  @override
  State<_InlineNotebookTextEditor> createState() =>
      _InlineNotebookTextEditorState();
}

class _InlineNotebookTextEditorState extends State<_InlineNotebookTextEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.object.textValue ?? '');
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focusNode = FocusNode(debugLabel: 'notebook-inline-text');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _InlineNotebookTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external = widget.object.textValue ?? '';
    if (!_focusNode.hasFocus && external != _controller.text) {
      _controller.value = TextEditingValue(
        text: external,
        selection: TextSelection.collapsed(offset: external.length),
      );
    }
  }

  TextStyle get _style => TextStyle(
    color: Color(widget.object.colorValue),
    fontSize: widget.object.fontSize ?? 12,
    fontFamily: widget.object.fontFamily ?? 'Arial',
    fontWeight: widget.object.fontBold ? FontWeight.bold : FontWeight.normal,
    fontStyle: widget.object.fontItalic ? FontStyle.italic : FontStyle.normal,
    decoration: widget.object.fontUnderline ? TextDecoration.underline : null,
    height: 1.25,
  );

  void _emit() {
    widget.onChanged?.call(
      widget.object.copyWith(
        textValue: _controller.text,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _finish() {
    _emit();
    widget.onEditingComplete?.call(
      widget.object.copyWith(
        textValue: _controller.text,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      expands: true,
      minLines: null,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textAlign: _notebookFlutterTextAlign(widget.object.textAlign),
      textAlignVertical: TextAlignVertical.top,
      style: _style,
      cursorColor: Theme.of(context).colorScheme.primary,
      decoration: const InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        border: InputBorder.none,
      ),
      onChanged: (_) => _emit(),
      onEditingComplete: _finish,
      onTapOutside: (_) {
        _focusNode.unfocus();
        _finish();
      },
    );
  }
}

class _NotebookShapePainter extends CustomPainter {
  const _NotebookShapePainter(this.object);

  final NotebookObject object;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Color(object.colorValue)
      ..strokeWidth = object.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = object.fillColorValue == null
        ? null
        : (Paint()
            ..color = Color(object.fillColorValue!)
            ..style = PaintingStyle.fill);
    final rect = Offset.zero & size;

    switch (object.type) {
      case NotebookObjectType.line:
        final y = size.height / 2;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke);
        return;
      case NotebookObjectType.arrow:
        final start = Offset(0, size.height / 2);
        final end = Offset(size.width, size.height / 2);
        canvas.drawLine(start, end, stroke);
        const headLength = 14.0;
        const headAngle = math.pi / 6;
        canvas.drawLine(
          end,
          end - Offset(math.cos(headAngle), math.sin(headAngle)) * headLength,
          stroke,
        );
        canvas.drawLine(
          end,
          end - Offset(math.cos(headAngle), -math.sin(headAngle)) * headLength,
          stroke,
        );
        return;
      case NotebookObjectType.rectangle:
        if (fill != null) canvas.drawRect(rect, fill);
        canvas.drawRect(rect.deflate(object.strokeWidth / 2), stroke);
        return;
      case NotebookObjectType.ellipse:
        if (fill != null) canvas.drawOval(rect, fill);
        canvas.drawOval(rect.deflate(object.strokeWidth / 2), stroke);
        return;
      case NotebookObjectType.triangle:
        final path = Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        if (fill != null) canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
        return;
      case NotebookObjectType.text:
      case NotebookObjectType.image:
        return;
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookShapePainter oldDelegate) =>
      oldDelegate.object != object;
}
