import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_models.dart';

class PdfInkPageOverlay extends StatefulWidget {
  const PdfInkPageOverlay({
    required this.documentId,
    required this.pageNumber,
    required this.strokes,
    required this.enabled,
    required this.tool,
    required this.colorValue,
    required this.strokeWidth,
    required this.onStrokeCompleted,
    this.onStrokeErased,
    this.eraserMode = false,
    this.eraserRadius = 18,
    super.key,
  });

  final String documentId;
  final int pageNumber;
  final List<PdfInkStroke> strokes;
  final bool enabled;
  final InkTool tool;
  final int colorValue;
  final double strokeWidth;
  final bool eraserMode;
  final double eraserRadius;
  final ValueChanged<PdfInkStroke> onStrokeCompleted;
  final ValueChanged<PdfInkStroke>? onStrokeErased;

  @override
  State<PdfInkPageOverlay> createState() => _PdfInkPageOverlayState();
}

class _PdfInkPageOverlayState extends State<PdfInkPageOverlay> {
  final List<InkPoint> _active = [];
  int? _pointer;
  Size _size = Size.zero;

  bool _accept(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse;
  }

  bool _isErasing(PointerEvent event) =>
      widget.eraserMode || event.kind == PointerDeviceKind.invertedStylus;

  InkPoint _point(PointerEvent event) {
    final pressure = event.pressureMax > event.pressureMin
        ? ((event.pressure - event.pressureMin) /
                (event.pressureMax - event.pressureMin))
            .clamp(0.0, 1.0)
        : 1.0;
    return InkPoint(
      x: _size.width == 0
          ? 0
          : (event.localPosition.dx / _size.width).clamp(0.0, 1.0),
      y: _size.height == 0
          ? 0
          : (event.localPosition.dy / _size.height).clamp(0.0, 1.0),
      pressure: pressure,
      tilt: event.tilt,
      timestampMicros: event.timeStamp.inMicroseconds,
    );
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null || !_accept(event)) return;
    _pointer = event.pointer;
    if (_isErasing(event)) {
      _eraseAt(event.localPosition);
      return;
    }
    _active
      ..clear()
      ..add(_point(event));
    setState(() {});
  }

  void _move(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    if (_isErasing(event)) {
      _eraseAt(event.localPosition);
      return;
    }
    _active.add(_point(event));
    setState(() {});
  }

  void _up(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    if (_isErasing(event)) {
      _pointer = null;
      _active.clear();
      setState(() {});
      return;
    }
    _active.add(_point(event));
    if (_active.length >= 2) {
      final now = DateTime.now().toUtc();
      widget.onStrokeCompleted(
        PdfInkStroke(
          id: 'pdf-${now.microsecondsSinceEpoch.toRadixString(36)}',
          documentId: widget.documentId,
          pageNumber: widget.pageNumber,
          tool: widget.tool,
          colorValue: widget.colorValue,
          opacity: widget.tool == InkTool.highlighter ? 0.28 : 1.0,
          width: widget.strokeWidth,
          points: List.unmodifiable(_active),
          createdAt: now,
        ),
      );
    }
    _pointer = null;
    _active.clear();
    setState(() {});
  }

  void _cancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _active.clear();
    setState(() {});
  }

  void _eraseAt(Offset position) {
    if (widget.strokes.isEmpty || _size.isEmpty) return;
    PdfInkStroke? hit;
    for (final stroke in widget.strokes.reversed) {
      if (_strokeHits(stroke, position, widget.eraserRadius)) {
        hit = stroke;
        break;
      }
    }
    if (hit != null) widget.onStrokeErased?.call(hit);
  }

  bool _strokeHits(PdfInkStroke stroke, Offset position, double radius) {
    final radiusSquared = radius * radius;
    final points = stroke.points;
    for (final point in points) {
      final dx = point.x * _size.width - position.dx;
      final dy = point.y * _size.height - position.dy;
      if (dx * dx + dy * dy <= radiusSquared) return true;
    }

    for (var index = 1; index < points.length; index++) {
      final a = points[index - 1];
      final b = points[index];
      if (_distanceToSegmentSquared(
            position.dx,
            position.dy,
            a.x * _size.width,
            a.y * _size.height,
            b.x * _size.width,
            b.y * _size.height,
          ) <=
          radiusSquared) {
        return true;
      }
    }
    return false;
  }

  double _distanceToSegmentSquared(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final abx = bx - ax;
    final aby = by - ay;
    final lengthSquared = abx * abx + aby * aby;
    if (lengthSquared == 0) {
      final dx = px - ax;
      final dy = py - ay;
      return dx * dx + dy * dy;
    }
    final t = (((px - ax) * abx + (py - ay) * aby) / lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    final nearestX = ax + abx * t;
    final nearestY = ay + aby * t;
    return math.pow(px - nearestX, 2).toDouble() +
        math.pow(py - nearestY, 2).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return IgnorePointer(
          ignoring: !widget.enabled,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: CustomPaint(
              painter: _PdfInkPainter(
                strokes: widget.strokes,
                active: _active,
                tool: widget.tool,
                colorValue: widget.colorValue,
                width: widget.strokeWidth,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _PdfInkPainter extends CustomPainter {
  const _PdfInkPainter({
    required this.strokes,
    required this.active,
    required this.tool,
    required this.colorValue,
    required this.width,
  });

  final List<PdfInkStroke> strokes;
  final List<InkPoint> active;
  final InkTool tool;
  final int colorValue;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(
        canvas,
        size,
        stroke.points,
        stroke.tool,
        stroke.colorValue,
        stroke.width,
        stroke.opacity,
      );
    }
    if (active.length >= 2) {
      _paintStroke(
        canvas,
        size,
        active,
        tool,
        colorValue,
        width,
        tool == InkTool.highlighter ? 0.28 : 1.0,
      );
    }
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    List<InkPoint> points,
    InkTool tool,
    int colorValue,
    double baseWidth,
    double opacity,
  ) {
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final pressure = ((a.pressure + b.pressure) / 2).clamp(0.15, 1.0);
      final strokeWidth = tool == InkTool.highlighter
          ? baseWidth
          : baseWidth * (0.45 + pressure * 0.75);
      canvas.drawLine(
        Offset(a.x * size.width, a.y * size.height),
        Offset(b.x * size.width, b.y * size.height),
        Paint()
          ..color = Color(colorValue).withValues(alpha: opacity)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PdfInkPainter oldDelegate) => true;
}
