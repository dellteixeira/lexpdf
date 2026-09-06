import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_eraser.dart';
import '../core/ink/pdf_ink_lasso.dart';
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
    this.onEraseApplied,
    this.onSelectionChanged,
    this.eraserMode = false,
    this.lassoMode = false,
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
  final bool lassoMode;
  final double eraserRadius;
  final ValueChanged<PdfInkStroke> onStrokeCompleted;
  final ValueChanged<PdfInkStroke>? onStrokeErased;
  final ValueChanged<PdfInkEraseResult>? onEraseApplied;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<PdfInkPageOverlay> createState() => PdfInkPageOverlayState();
}

class PdfInkPageOverlayState extends State<PdfInkPageOverlay> {
  static const _eraser = PdfInkEraser();
  static const _lasso = PdfInkLasso();

  final List<InkPoint> _active = [];
  final List<Offset> _lassoPoints = [];
  final Set<String> _selectedStrokeIds = <String>{};
  int? _pointer;
  Size _size = Size.zero;

  Set<String> get selectedStrokeIds => Set.unmodifiable(_selectedStrokeIds);

  @override
  void didUpdateWidget(covariant PdfInkPageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedStrokeIds.removeWhere(
      (id) => !widget.strokes.any((stroke) => stroke.id == id),
    );
    if (oldWidget.lassoMode && !widget.lassoMode) {
      _lassoPoints.clear();
      clearSelection();
    }
  }

  void clearSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _selectedStrokeIds.clear();
    widget.onSelectionChanged?.call(const <String>{});
    if (mounted) setState(() {});
  }

  bool _accept(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse;
  }

  bool _isErasing(PointerEvent event) =>
      !widget.lassoMode &&
      (widget.eraserMode || event.kind == PointerDeviceKind.invertedStylus);

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

  Offset _normalizedOffset(Offset local) => Offset(
        _size.width == 0 ? 0 : (local.dx / _size.width).clamp(0.0, 1.0),
        _size.height == 0 ? 0 : (local.dy / _size.height).clamp(0.0, 1.0),
      );

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null || !_accept(event)) return;
    _pointer = event.pointer;
    if (widget.lassoMode) {
      _lassoPoints
        ..clear()
        ..add(event.localPosition);
      _selectedStrokeIds.clear();
      widget.onSelectionChanged?.call(const <String>{});
      setState(() {});
      return;
    }
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
    if (widget.lassoMode) {
      _lassoPoints.add(event.localPosition);
      setState(() {});
      return;
    }
    if (_isErasing(event)) {
      _eraseAt(event.localPosition);
      return;
    }
    _active.add(_point(event));
    setState(() {});
  }

  void _up(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    if (widget.lassoMode) {
      _lassoPoints.add(event.localPosition);
      final polygon = _lassoPoints.map(_normalizedOffset).toList(growable: false);
      final selected = _lasso.selectStrokes(
        strokes: widget.strokes,
        polygon: polygon,
      );
      _selectedStrokeIds
        ..clear()
        ..addAll(selected);
      _pointer = null;
      widget.onSelectionChanged?.call(Set.unmodifiable(_selectedStrokeIds));
      setState(() {});
      return;
    }
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
    _lassoPoints.clear();
    setState(() {});
  }

  void _eraseAt(Offset position) {
    if (widget.strokes.isEmpty || _size.isEmpty) return;
    for (final stroke in widget.strokes.reversed) {
      final result = _eraser.eraseAt(
        stroke: stroke,
        localX: position.dx,
        localY: position.dy,
        pageWidth: _size.width,
        pageHeight: _size.height,
        radius: widget.eraserRadius,
      );
      if (result == null) continue;

      _selectedStrokeIds.remove(result.original.id);
      if (widget.onEraseApplied != null) {
        widget.onEraseApplied!(result);
      } else {
        widget.onStrokeErased?.call(result.original);
        for (final fragment in result.fragments) {
          widget.onStrokeCompleted(fragment);
        }
      }
      widget.onSelectionChanged?.call(Set.unmodifiable(_selectedStrokeIds));
      return;
    }
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
                lassoPoints: _lassoPoints,
                selectedStrokeIds: _selectedStrokeIds,
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
    required this.lassoPoints,
    required this.selectedStrokeIds,
    required this.tool,
    required this.colorValue,
    required this.width,
  });

  final List<PdfInkStroke> strokes;
  final List<InkPoint> active;
  final List<Offset> lassoPoints;
  final Set<String> selectedStrokeIds;
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
    _paintSelectionBounds(canvas, size);
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

  void _paintSelectionBounds(Canvas canvas, Size size) {
    final bounds = const PdfInkLasso().selectionBounds(
      strokes: strokes,
      selectedIds: selectedStrokeIds,
    );
    if (bounds == null) return;
    canvas.drawRect(
      Rect.fromLTRB(
        bounds.left * size.width,
        bounds.top * size.height,
        bounds.right * size.width,
        bounds.bottom * size.height,
      ).inflate(6),
      Paint()
        ..color = Colors.blueGrey.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
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
