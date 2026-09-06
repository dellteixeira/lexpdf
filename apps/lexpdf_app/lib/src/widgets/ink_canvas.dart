import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/ink/ink_lasso.dart';
import '../core/ink/ink_models.dart';

class InkCanvas extends StatefulWidget {
  const InkCanvas({
    required this.initialStrokes,
    required this.pageId,
    required this.tool,
    required this.colorValue,
    required this.strokeWidth,
    required this.onStrokeCompleted,
    this.onStrokeUpdated,
    this.onStrokeErased,
    this.onSelectionChanged,
    this.stylusOnly = true,
    this.eraserMode = false,
    this.lassoMode = false,
    this.eraserRadius = 18,
    super.key,
  });

  final List<InkStroke> initialStrokes;
  final String pageId;
  final InkTool tool;
  final int colorValue;
  final double strokeWidth;
  final bool stylusOnly;
  final bool eraserMode;
  final bool lassoMode;
  final double eraserRadius;
  final ValueChanged<InkStroke> onStrokeCompleted;
  final ValueChanged<InkStroke>? onStrokeUpdated;
  final ValueChanged<InkStroke>? onStrokeErased;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<InkCanvas> createState() => InkCanvasState();
}

class InkCanvasState extends State<InkCanvas> {
  static const _lasso = InkLasso();

  final List<InkStroke> _strokes = <InkStroke>[];
  final List<InkPoint> _activePoints = <InkPoint>[];
  final List<Offset> _lassoPoints = <Offset>[];
  final Set<String> _selectedStrokeIds = <String>{};
  final Set<int> _ignoredTouchPointers = <int>{};
  int? _activePointer;
  bool _stylusActive = false;

  List<InkStroke> get strokes => List.unmodifiable(_strokes);
  Set<String> get selectedStrokeIds => Set.unmodifiable(_selectedStrokeIds);

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
      _selectedStrokeIds.removeWhere(
        (id) => !_strokes.any((stroke) => stroke.id == id),
      );
    }
    if (oldWidget.lassoMode && !widget.lassoMode) {
      _lassoPoints.clear();
      _clearSelection();
    }
  }

  InkStroke? undoLast() {
    if (_strokes.isEmpty) return null;
    final removed = _strokes.removeLast();
    _selectedStrokeIds.remove(removed.id);
    _notifySelection();
    setState(() {});
    return removed;
  }

  List<InkStroke> deleteSelected() {
    if (_selectedStrokeIds.isEmpty) return const [];
    final removed = _strokes
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .toList(growable: false);
    _strokes.removeWhere((stroke) => _selectedStrokeIds.contains(stroke.id));
    _selectedStrokeIds.clear();
    _notifySelection();
    setState(() {});
    return removed;
  }

  List<InkStroke> moveSelected(double dx, double dy) {
    if (_selectedStrokeIds.isEmpty || (dx == 0 && dy == 0)) return const [];
    final updated = <InkStroke>[];
    for (var index = 0; index < _strokes.length; index++) {
      final stroke = _strokes[index];
      if (!_selectedStrokeIds.contains(stroke.id)) continue;
      final moved = InkStroke(
        id: stroke.id,
        pageId: stroke.pageId,
        tool: stroke.tool,
        colorValue: stroke.colorValue,
        opacity: stroke.opacity,
        width: stroke.width,
        points: List<InkPoint>.unmodifiable(
          stroke.points.map(
            (point) => InkPoint(
              x: point.x + dx,
              y: point.y + dy,
              pressure: point.pressure,
              tilt: point.tilt,
              timestampMicros: point.timestampMicros,
            ),
          ),
        ),
        createdAt: stroke.createdAt,
      );
      _strokes[index] = moved;
      updated.add(moved);
      widget.onStrokeUpdated?.call(moved);
    }
    setState(() {});
    return List.unmodifiable(updated);
  }

  void clearSelection() => _clearSelection();

  void clear() {
    _strokes.clear();
    _activePoints.clear();
    _lassoPoints.clear();
    _selectedStrokeIds.clear();
    _ignoredTouchPointers.clear();
    _activePointer = null;
    _stylusActive = false;
    _notifySelection();
    setState(() {});
  }

  bool _isStylus(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  bool _accept(PointerEvent event) {
    if (_isStylus(event)) return true;
    if (_stylusActive && event.kind == PointerDeviceKind.touch) return false;
    if (event.kind == PointerDeviceKind.mouse) return true;
    return !widget.stylusOnly && event.kind == PointerDeviceKind.touch;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_isStylus(event)) _stylusActive = true;
    if (event.kind == PointerDeviceKind.touch && _stylusActive) {
      _ignoredTouchPointers.add(event.pointer);
      return;
    }
    if (_activePointer != null || !_accept(event)) return;
    _activePointer = event.pointer;

    if (widget.lassoMode) {
      _lassoPoints
        ..clear()
        ..add(event.localPosition);
      _clearSelection(notify: false);
      setState(() {});
      return;
    }
    if (widget.eraserMode || event.kind == PointerDeviceKind.invertedStylus) {
      _eraseAt(event.localPosition);
      return;
    }
    _activePoints
      ..clear()
      ..add(_pointFromEvent(event));
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_ignoredTouchPointers.contains(event.pointer)) return;
    if (_activePointer != event.pointer) return;
    if (widget.lassoMode) {
      _lassoPoints.add(event.localPosition);
      setState(() {});
      return;
    }
    if (widget.eraserMode || event.kind == PointerDeviceKind.invertedStylus) {
      _eraseAt(event.localPosition);
      return;
    }
    _activePoints.add(_pointFromEvent(event));
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_ignoredTouchPointers.remove(event.pointer)) return;
    if (_activePointer != event.pointer) {
      if (_isStylus(event)) _stylusActive = false;
      return;
    }
    if (widget.lassoMode) {
      _lassoPoints.add(event.localPosition);
      final selected = _lasso.selectStrokes(strokes: _strokes, polygon: _lassoPoints);
      _selectedStrokeIds
        ..clear()
        ..addAll(selected);
      _activePointer = null;
      _notifySelection();
      if (_isStylus(event)) _stylusActive = false;
      setState(() {});
      return;
    }
    if (widget.eraserMode || event.kind == PointerDeviceKind.invertedStylus) {
      _activePointer = null;
      if (_isStylus(event)) _stylusActive = false;
      setState(() {});
      return;
    }
    _finishStroke(event);
    if (_isStylus(event)) _stylusActive = false;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _ignoredTouchPointers.remove(event.pointer);
    if (_activePointer == event.pointer) {
      _activePoints.clear();
      _lassoPoints.clear();
      _activePointer = null;
    }
    if (_isStylus(event)) _stylusActive = false;
    setState(() {});
  }

  void _clearSelection({bool notify = true}) {
    if (_selectedStrokeIds.isEmpty) return;
    _selectedStrokeIds.clear();
    if (notify) _notifySelection();
    setState(() {});
  }

  void _notifySelection() {
    widget.onSelectionChanged?.call(Set.unmodifiable(_selectedStrokeIds));
  }

  void _eraseAt(Offset position) {
    if (_strokes.isEmpty) return;
    InkStroke? hit;
    for (final stroke in _strokes.reversed) {
      if (_strokeHits(stroke, position, widget.eraserRadius)) {
        hit = stroke;
        break;
      }
    }
    if (hit == null) return;
    _strokes.remove(hit);
    _selectedStrokeIds.remove(hit.id);
    widget.onStrokeErased?.call(hit);
    _notifySelection();
    setState(() {});
  }

  bool _strokeHits(InkStroke stroke, Offset position, double radius) {
    final radiusSquared = radius * radius;
    for (final point in stroke.points) {
      final dx = point.x - position.dx;
      final dy = point.y - position.dy;
      if (dx * dx + dy * dy <= radiusSquared) return true;
    }
    for (var index = 1; index < stroke.points.length; index++) {
      final a = stroke.points[index - 1];
      final b = stroke.points[index];
      if (_distanceToSegmentSquared(position.dx, position.dy, a.x, a.y, b.x, b.y) <= radiusSquared) {
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
          lassoPoints: _lassoPoints,
          selectedStrokeIds: _selectedStrokeIds,
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
    required this.lassoPoints,
    required this.selectedStrokeIds,
    required this.activeTool,
    required this.activeColorValue,
    required this.activeWidth,
  });

  final List<InkStroke> strokes;
  final List<InkPoint> activePoints;
  final List<Offset> lassoPoints;
  final Set<String> selectedStrokeIds;
  final InkTool activeTool;
  final int activeColorValue;
  final double activeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke.points, stroke.tool, stroke.colorValue, stroke.width, stroke.opacity);
      if (selectedStrokeIds.contains(stroke.id)) _paintSelectionBounds(canvas, stroke);
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
    if (lassoPoints.length >= 2) {
      final path = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      for (final point in lassoPoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.blueGrey.withValues(alpha: 0.85)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintSelectionBounds(Canvas canvas, InkStroke stroke) {
    if (stroke.points.isEmpty) return;
    var minX = stroke.points.first.x;
    var minY = stroke.points.first.y;
    var maxX = minX;
    var maxY = minY;
    for (final point in stroke.points.skip(1)) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    canvas.drawRect(
      Rect.fromLTRB(minX, minY, maxX, maxY).inflate(4),
      Paint()
        ..color = Colors.blueGrey.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
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
