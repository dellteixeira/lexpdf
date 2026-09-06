import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/notebook/notebook_object_models.dart';

class NotebookObjectLayer extends StatefulWidget {
  const NotebookObjectLayer({
    required this.objects,
    required this.enabled,
    required this.onObjectChanged,
    required this.onSelectionChanged,
    this.onObjectDoubleTap,
    this.selectedId,
    super.key,
  });

  final List<NotebookObject> objects;
  final bool enabled;
  final String? selectedId;
  final ValueChanged<NotebookObject> onObjectChanged;
  final ValueChanged<String?> onSelectionChanged;
  final ValueChanged<NotebookObject>? onObjectDoubleTap;

  @override
  State<NotebookObjectLayer> createState() => _NotebookObjectLayerState();
}

class _NotebookObjectLayerState extends State<NotebookObjectLayer> {
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
            onTap: () => widget.onSelectionChanged(null),
          ),
          for (final raw in widget.objects)
            _buildObject(_effective(raw), widget.selectedId == raw.id),
        ],
      ),
    );
  }

  Widget _buildObject(NotebookObject object, bool selected) {
    final safeWidth = math.max(24.0, object.width);
    final safeHeight = math.max(24.0, object.height);
    return Positioned(
      left: object.x,
      top: object.y,
      width: safeWidth,
      height: safeHeight,
      child: Transform.rotate(
        angle: object.rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelectionChanged(object.id),
          onDoubleTap: () {
            widget.onSelectionChanged(object.id);
            widget.onObjectDoubleTap?.call(object);
          },
          onPanStart: (_) {
            widget.onSelectionChanged(object.id);
            _working = object;
          },
          onPanUpdate: (details) {
            final current = _working ?? object;
            final next = current.copyWith(
              x: current.x + details.delta.dx,
              y: current.y + details.delta.dy,
              updatedAt: DateTime.now().toUtc(),
            );
            setState(() => _working = next);
          },
          onPanEnd: (_) {
            final next = _working;
            _working = null;
            if (next != null) widget.onObjectChanged(next);
            setState(() {});
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: _ObjectVisual(object: object)),
              if (selected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => _working = object,
                    onPanUpdate: (details) {
                      final current = _working ?? object;
                      final next = current.copyWith(
                        width: math.max(24, current.width + details.delta.dx),
                        height: math.max(24, current.height + details.delta.dy),
                        updatedAt: DateTime.now().toUtc(),
                      );
                      setState(() => _working = next);
                    },
                    onPanEnd: (_) {
                      final next = _working;
                      _working = null;
                      if (next != null) widget.onObjectChanged(next);
                      setState(() {});
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObjectVisual extends StatelessWidget {
  const _ObjectVisual({required this.object});

  final NotebookObject object;

  @override
  Widget build(BuildContext context) {
    if (object.type == NotebookObjectType.text) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          object.textValue ?? '',
          maxLines: null,
          style: TextStyle(
            color: Color(object.colorValue),
            fontSize: object.fontSize ?? 18,
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
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }
    return CustomPaint(
      painter: _NotebookShapePainter(object),
      child: const SizedBox.expand(),
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
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), stroke);
        return;
      case NotebookObjectType.arrow:
        final start = Offset.zero;
        final end = Offset(size.width, size.height);
        canvas.drawLine(start, end, stroke);
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        const headLength = 14.0;
        canvas.drawLine(
          end,
          end - Offset(math.cos(angle - math.pi / 6), math.sin(angle - math.pi / 6)) * headLength,
          stroke,
        );
        canvas.drawLine(
          end,
          end - Offset(math.cos(angle + math.pi / 6), math.sin(angle + math.pi / 6)) * headLength,
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
