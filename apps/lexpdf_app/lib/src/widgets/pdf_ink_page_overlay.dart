import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_eraser.dart';
import '../core/ink/pdf_ink_lasso.dart';
import '../core/ink/pdf_ink_models.dart';
import '../core/ink/pdf_ink_selection_ops.dart';

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
    this.onStrokeUpdated,
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
  final ValueChanged<PdfInkStroke>? onStrokeUpdated;
  final ValueChanged<PdfInkEraseResult>? onEraseApplied;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<PdfInkPageOverlay> createState() => PdfInkPageOverlayState();
}

class PdfInkPageOverlayState extends State<PdfInkPageOverlay> {
  static const _eraser = PdfInkEraser();
  static const _lasso = PdfInkLasso();
  static const _selectionOps = PdfInkSelectionOps();
  static const double _moveStep = 0.02;
  static const double _pasteOffset = 0.02;
  static List<PdfInkStroke> _clipboard = const [];

  final List<InkPoint> _active = [];
  final List<Offset> _lassoPoints = [];
  final Set<String> _selectedStrokeIds = <String>{};
  int? _pointer;
  Size _size = Size.zero;
  bool _localLassoMode = false;

  Set<String> get selectedStrokeIds => Set.unmodifiable(_selectedStrokeIds);
  bool get hasClipboard => _clipboard.isNotEmpty;
  bool get _lassoEnabled => widget.lassoMode || _localLassoMode;

  @override
  void didUpdateWidget(covariant PdfInkPageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedStrokeIds.removeWhere(
      (id) => !widget.strokes.any((stroke) => stroke.id == id),
    );
    if (oldWidget.lassoMode && !widget.lassoMode && !_localLassoMode) {
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
      !_lassoEnabled &&
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
    if (_lassoEnabled) {
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
    if (_lassoEnabled) {
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
    if (_lassoEnabled) {
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

  List<PdfInkStroke> _selectedStrokes() => widget.strokes
      .where((stroke) => _selectedStrokeIds.contains(stroke.id))
      .toList(growable: false);

  void _applyUpdated(List<PdfInkStroke> updated) {
    if (updated.isEmpty) return;
    for (final stroke in updated) {
      if (widget.onStrokeUpdated != null) {
        widget.onStrokeUpdated!(stroke);
        continue;
      }
      final original = widget.strokes.firstWhere(
        (candidate) => candidate.id == stroke.id,
      );
      widget.onStrokeErased?.call(original);
      widget.onStrokeCompleted(stroke);
    }
    if (mounted) setState(() {});
  }

  void _moveSelected(double dx, double dy) {
    _applyUpdated(
      _selectionOps.move(
        strokes: widget.strokes,
        selectedIds: _selectedStrokeIds,
        dx: dx,
        dy: dy,
      ),
    );
  }

  void _scaleSelected(double factor) {
    _applyUpdated(
      _selectionOps.scale(
        strokes: widget.strokes,
        selectedIds: _selectedStrokeIds,
        factor: factor,
      ),
    );
  }

  void _rotateSelected(double angle) {
    _applyUpdated(
      _selectionOps.rotate(
        strokes: widget.strokes,
        selectedIds: _selectedStrokeIds,
        angleRadians: angle,
      ),
    );
  }

  void _applyCurrentColor() {
    _applyUpdated(
      _selectionOps.recolor(
        strokes: widget.strokes,
        selectedIds: _selectedStrokeIds,
        colorValue: widget.colorValue,
      ),
    );
  }

  void _applyCurrentWidth() {
    _applyUpdated(
      _selectionOps.setWidth(
        strokes: widget.strokes,
        selectedIds: _selectedStrokeIds,
        width: widget.strokeWidth,
      ),
    );
  }

  void _copySelected() {
    final selected = _selectedStrokes();
    if (selected.isEmpty) return;
    _clipboard = selected.map(_snapshotStroke).toList(growable: false);
    setState(() {});
  }

  void _cutSelected() {
    _copySelected();
    _deleteSelected();
  }

  void _deleteSelected() {
    final selected = _selectedStrokes();
    if (selected.isEmpty) return;
    for (final stroke in selected) {
      widget.onStrokeErased?.call(stroke);
    }
    _selectedStrokeIds.clear();
    widget.onSelectionChanged?.call(const <String>{});
    if (mounted) setState(() {});
  }

  void _duplicateSelected() {
    final selected = _selectedStrokes();
    if (selected.isEmpty) return;
    _insertCopies(selected);
  }

  void _pasteClipboard() {
    if (_clipboard.isEmpty) return;
    _insertCopies(_clipboard);
  }

  void _insertCopies(List<PdfInkStroke> source) {
    final now = DateTime.now().toUtc();
    for (var index = 0; index < source.length; index++) {
      final original = source[index];
      final createdAt = now.add(Duration(microseconds: index));
      widget.onStrokeCompleted(
        PdfInkStroke(
          id: 'pdf-${createdAt.microsecondsSinceEpoch.toRadixString(36)}-$index',
          documentId: widget.documentId,
          pageNumber: widget.pageNumber,
          tool: original.tool,
          colorValue: original.colorValue,
          opacity: original.opacity,
          width: original.width,
          points: List<InkPoint>.unmodifiable(
            original.points.map(
              (point) => _copyPoint(
                point,
                x: (point.x + _pasteOffset).clamp(0.0, 1.0),
                y: (point.y + _pasteOffset).clamp(0.0, 1.0),
              ),
            ),
          ),
          createdAt: createdAt,
        ),
      );
    }
  }

  PdfInkStroke _snapshotStroke(PdfInkStroke stroke) => PdfInkStroke(
        id: stroke.id,
        documentId: stroke.documentId,
        pageNumber: stroke.pageNumber,
        tool: stroke.tool,
        colorValue: stroke.colorValue,
        opacity: stroke.opacity,
        width: stroke.width,
        points: List<InkPoint>.unmodifiable(stroke.points),
        createdAt: stroke.createdAt,
      );

  InkPoint _copyPoint(
    InkPoint point, {
    required double x,
    required double y,
  }) {
    return InkPoint(
      x: x,
      y: y,
      pressure: point.pressure,
      tilt: point.tilt,
      timestampMicros: point.timestampMicros,
    );
  }

  void _toggleLocalLasso() {
    setState(() {
      _localLassoMode = !_localLassoMode;
      _lassoPoints.clear();
      if (!_localLassoMode) {
        _selectedStrokeIds.clear();
        widget.onSelectionChanged?.call(const <String>{});
      }
    });
  }

  void _handleSelectionAction(String action) {
    switch (action) {
      case 'left':
        _moveSelected(-_moveStep, 0);
      case 'right':
        _moveSelected(_moveStep, 0);
      case 'up':
        _moveSelected(0, -_moveStep);
      case 'down':
        _moveSelected(0, _moveStep);
      case 'shrink':
        _scaleSelected(0.9);
      case 'grow':
        _scaleSelected(1.1);
      case 'rotate-left':
        _rotateSelected(-math.pi / 12);
      case 'rotate-right':
        _rotateSelected(math.pi / 12);
      case 'copy':
        _copySelected();
      case 'duplicate':
        _duplicateSelected();
      case 'cut':
        _cutSelected();
      case 'color':
        _applyCurrentColor();
      case 'width':
        _applyCurrentWidth();
      case 'delete':
        _deleteSelected();
    }
  }

  Widget _buildSelectionControls(BuildContext context) {
    final selectedCount = _selectedStrokeIds.length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _lassoEnabled ? 'Sair do laço' : 'Selecionar com laço',
              visualDensity: VisualDensity.compact,
              onPressed: _toggleLocalLasso,
              icon: Icon(_lassoEnabled ? Icons.close : Icons.gesture),
              color: _lassoEnabled ? Theme.of(context).colorScheme.primary : null,
            ),
            if (selectedCount > 0)
              PopupMenuButton<String>(
                tooltip: '$selectedCount traço(s) selecionado(s)',
                icon: Badge(
                  label: Text('$selectedCount'),
                  child: const Icon(Icons.select_all),
                ),
                onSelected: _handleSelectionAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'left', child: Text('Mover para esquerda')),
                  PopupMenuItem(value: 'right', child: Text('Mover para direita')),
                  PopupMenuItem(value: 'up', child: Text('Mover para cima')),
                  PopupMenuItem(value: 'down', child: Text('Mover para baixo')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'shrink', child: Text('Diminuir 10%')),
                  PopupMenuItem(value: 'grow', child: Text('Aumentar 10%')),
                  PopupMenuItem(value: 'rotate-left', child: Text('Girar 15° à esquerda')),
                  PopupMenuItem(value: 'rotate-right', child: Text('Girar 15° à direita')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'copy', child: Text('Copiar')),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
                  PopupMenuItem(value: 'cut', child: Text('Recortar')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'color', child: Text('Aplicar cor atual')),
                  PopupMenuItem(value: 'width', child: Text('Aplicar espessura atual')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Excluir seleção')),
                ],
              ),
            if (_clipboard.isNotEmpty)
              IconButton(
                tooltip: 'Colar',
                visualDensity: VisualDensity.compact,
                onPressed: _pasteClipboard,
                icon: const Icon(Icons.content_paste),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return IgnorePointer(
          ignoring: !widget.enabled,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
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
              if (!widget.eraserMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildSelectionControls(context),
                ),
            ],
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
