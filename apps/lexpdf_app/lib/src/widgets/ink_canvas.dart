import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';

class InkCanvas extends StatefulWidget {
  const InkCanvas({
    required this.initialStrokes,
    required this.pageId,
    required this.tool,
    required this.colorValue,
    required this.strokeWidth,
    required this.onStrokeCompleted,
    this.stylusOnly = true,
    super.key,
  });

  final List<InkStroke> initialStrokes;
  final String pageId;
  final InkTool tool;
  final int colorValue;
  final double strokeWidth;
  final bool stylusOnly;
  final ValueChanged<InkStroke> onStrokeCompleted;

  @override
  State<InkCanvas> createState() => InkCanvasState();
}

class InkCanvasState extends State<InkCanvas> {
  final List<InkStroke> _strokes = <InkStroke>[];
  final List<InkPoint> _activePoints = <InkPoint>[];
  int? _activePointer;

  List<InkStroke> get strokes => List.unmodifiable(_strokes);

  @override
  void initState() {
    super.initState();
    _strokes.addAll(widget.initialStrokes);
  }

  @override
  void didUpdateWidget(covariant InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStrokes != widget.initialStrokes && _activePointer == null) {
      _strokes
        ..clear()
        ..addAll(widget.initialStrokes);
    }
  }

  InkStroke? undoLast() {
    if (_strokes.isEmpty) return null;
    final removed = _strokes.removeLast();
    setState(() {});
    return removed;
  }

  void clear() {
    _strokes.clear();
    _activePoints.clear();
    _activePointer = null;
    setState(() {});
  }

  bool _accept(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return true;
    }
    if (event.kind == PointerDeviceKind.mouse) return true;
    return !widget.stylusOnly && event.kind == PointerDeviceKind.touch;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || !_accept(event)) return;
    _activePointer = event.pointer;
    _activePoints
      ..clear()
      ..add(_pointFromEvent(event));
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer) return;
    _activePoints.add(_pointFromEvent(event));
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) return;
    _finishStroke(event);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _activePoints.clear();
    _activePointer = null;
    setState(() {});
  }

  void _finishStroke(PointerEvent event) {
    _activePoints.add(_pointFromEvent(event));
    if (_activePoints.length >= 2) {
      final now = DateTime.now().toUtc();
      final stroke = InkStroke(
        id: now.microsecondsSinceEpoch.toRadixString(36),
        pageId: widget.pageId,
        tool: widget.tool,
        colorValue: widget.colorValue,
        opacity: widget.tool == InkTool.highlighter ? 0.28 : 1.0,
        width: widget.strokeWidth,
        points: List<InkPoint>.unmodifiable(_activePoints),
        createdAt: now,
      );
      _strokes.add(stroke);
      widget.onStrokeCompleted(stroke);
    }
    _activePoints.clear();
    _activePointer = null;
    setState(() {});
  }

  InkPoint _pointFromEvent(PointerEvent event) {
    final normalizedPressure = event.pressureMax > event.pressureMin
        ? ((event.pressure - event.pressureMin) /
                (event.pressureMax - event.pressureMin))
            .clamp(0.0, 1.0)
            .toDouble()
        : 1.0;
    return InkPoint(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      pressure: normalizedPressure,
      tilt: event.tilt,
      timestampMicros: event.timeStamp.inMicroseconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: CustomPaint(
        painter: _InkPainter(
          strokes: _strokes,
          activePoints: _activePoints,
          activeTool: widget.tool,
          activeColorValue: widget.colorValue,
          activeWidth: widget.strokeWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  const _InkPainter({
    required this.strokes,
    required this.activePoints,
    required this.activeTool,
    required this.activeColorValue,
    required this.activeWidth,
  });

  final List<InkStroke> strokes;
  final List<InkPoint> activePoints;
  final InkTool activeTool;
  final int activeColorValue;
  final double activeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(
        canvas,
        stroke.points,
        stroke.tool,
        stroke.colorValue,
        stroke.width,
        stroke.opacity,
      );
    }
    if (activePoints.length >= 2) {
      _paintStroke(
        canvas,
        activePoints,
        activeTool,
        activeColorValue,
        activeWidth,
        activeTool == InkTool.highlighter ? 0.28 : 1.0,
      );
    }
  }

  void _paintStroke(
    Canvas canvas,
    List<InkPoint> points,
    InkTool tool,
    int colorValue,
    double baseWidth,
    double opacity,
  ) {
    if (points.length < 2) return;
    final color = Color(colorValue).withValues(alpha: opacity);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final pressure = ((previous.pressure + current.pressure) / 2)
          .clamp(0.15, 1.0)
          .toDouble();
      final width = tool == InkTool.highlighter
          ? baseWidth
          : baseWidth * (0.45 + pressure * 0.75);
      canvas.drawLine(
        Offset(previous.x, previous.y),
        Offset(current.x, current.y),
        Paint()
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}
