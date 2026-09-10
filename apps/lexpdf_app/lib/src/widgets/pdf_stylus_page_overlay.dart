import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_eraser.dart';
import '../core/ink/pdf_ink_models.dart';

/// Stylus-first drawing surface for a PDF page.
///
/// Touch is intentionally ignored here so the PDF viewer can keep ownership of
/// finger navigation. Stylus, inverted stylus and mouse input are accepted.
class PdfStylusPageOverlay extends StatefulWidget {
  const PdfStylusPageOverlay({
    required this.documentId,
    required this.pageNumber,
    required this.strokes,
    required this.enabled,
    required this.tool,
    required this.colorValue,
    required this.strokeWidth,
    required this.eraserMode,
    required this.onStrokeCompleted,
    required this.onEraseApplied,
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
  final ValueChanged<PdfInkEraseResult> onEraseApplied;

  @override
  State<PdfStylusPageOverlay> createState() => _PdfStylusPageOverlayState();
}

class _PdfStylusPageOverlayState extends State<PdfStylusPageOverlay> {
  static const _eraser = PdfInkEraser();

  final List<InkPoint> _active = <InkPoint>[];
  int? _pointer;
  Size _size = Size.zero;

  bool _accept(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus ||
      event.kind == PointerDeviceKind.mouse;

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
    if (!_isErasing(event)) {
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
            opacity: widget.tool == InkTool.highlighter ? 0.24 : 1.0,
            width: widget.strokeWidth,
            points: List<InkPoint>.unmodifiable(_active),
            createdAt: now,
          ),
        );
      }
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
      widget.onEraseApplied(result);
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
              painter: _StylusInkPainter(
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

class _StylusInkPainter extends CustomPainter {
  const _StylusInkPainter({
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
        tool == InkTool.highlighter ? 0.24 : 1.0,
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
      final paint = Paint()
        ..color = Color(colorValue).withValues(alpha: opacity)
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (tool == InkTool.highlighter) {
        // Multiply behaves like real marker ink: dark glyphs remain crisp even
        // though the annotation is composited above the rendered PDF bitmap.
        paint.blendMode = BlendMode.multiply;
      }
      canvas.drawLine(
        Offset(a.x * size.width, a.y * size.height),
        Offset(b.x * size.width, b.y * size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StylusInkPainter oldDelegate) => true;
}
