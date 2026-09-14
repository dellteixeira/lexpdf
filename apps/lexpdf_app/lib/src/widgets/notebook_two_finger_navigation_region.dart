import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Adds notebook-style two-finger navigation without stealing one-finger input.
///
/// One finger remains available to the child (ink, text selection, object drag).
/// Two touch pointers temporarily take ownership of the viewport and update the
/// nearest [InteractiveViewer]'s [TransformationController] directly. Stylus
/// contact always has priority so palm/finger contact does not move the page
/// while the pen is down.
class NotebookTwoFingerNavigationRegion extends StatefulWidget {
  const NotebookTwoFingerNavigationRegion({
    required this.active,
    required this.child,
    this.minScale = 0.25,
    this.maxScale = 4.0,
    this.onNavigationChanged,
    super.key,
  });

  final bool active;
  final Widget child;
  final double minScale;
  final double maxScale;
  final ValueChanged<bool>? onNavigationChanged;

  @override
  State<NotebookTwoFingerNavigationRegion> createState() =>
      _NotebookTwoFingerNavigationRegionState();
}

class _NotebookTwoFingerNavigationRegionState
    extends State<NotebookTwoFingerNavigationRegion> {
  static const double _minimumVisibleExtent = 48;

  final Map<int, Offset> _touchPositions = <int, Offset>{};
  final Set<int> _stylusPointers = <int>{};

  bool _navigating = false;
  List<int> _gesturePointers = const <int>[];
  double _startDistance = 1;
  double _startScale = 1;
  Offset _startSceneFocal = Offset.zero;
  InteractiveViewer? _viewer;
  RenderBox? _viewerBox;

  @override
  void didUpdateWidget(covariant NotebookTwoFingerNavigationRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active && _navigating) {
      _finishNavigation();
    }
  }

  bool _isStylus(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.active) return;

    if (_isStylus(event)) {
      _stylusPointers.add(event.pointer);
      if (_navigating) _finishNavigation();
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;

    _touchPositions[event.pointer] = event.position;
    if (!_navigating &&
        _stylusPointers.isEmpty &&
        _touchPositions.length >= 2) {
      _beginNavigation();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.active || event.kind != PointerDeviceKind.touch) return;
    if (!_touchPositions.containsKey(event.pointer)) return;
    _touchPositions[event.pointer] = event.position;
    if (_navigating) _applyNavigation();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isStylus(event)) {
      _stylusPointers.remove(event.pointer);
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPositions.remove(event.pointer);
    _handlePointerDeparture(event.pointer);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isStylus(event)) {
      _stylusPointers.remove(event.pointer);
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPositions.remove(event.pointer);
    _handlePointerDeparture(event.pointer);
  }

  void _handlePointerDeparture(int pointer) {
    if (!_navigating || !_gesturePointers.contains(pointer)) return;
    if (_touchPositions.length >= 2 && _stylusPointers.isEmpty) {
      _rebaseNavigation();
    } else {
      _finishNavigation();
    }
  }

  void _beginNavigation() {
    final binding = _findViewerBinding();
    if (binding == null) return;

    _viewer = binding.viewer;
    _viewerBox = binding.box;
    _navigating = true;
    widget.onNavigationChanged?.call(true);
    _rebaseNavigation();
  }

  void _rebaseNavigation() {
    if (!_navigating) return;
    final controller = _viewer?.transformationController;
    final box = _viewerBox;
    if (controller == null || box == null || _touchPositions.length < 2) {
      _finishNavigation();
      return;
    }

    _gesturePointers = _touchPositions.keys.take(2).toList(growable: false);
    final first = _viewportPosition(_gesturePointers[0], box);
    final second = _viewportPosition(_gesturePointers[1], box);
    if (first == null || second == null) {
      _finishNavigation();
      return;
    }

    final focal = Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
    _startDistance = math.max((first - second).distance, 1.0);
    _startScale = controller.value.getMaxScaleOnAxis();
    _startSceneFocal = controller.toScene(focal);
  }

  void _applyNavigation() {
    final viewer = _viewer;
    final controller = viewer?.transformationController;
    final box = _viewerBox;
    if (!_navigating ||
        controller == null ||
        box == null ||
        _gesturePointers.length != 2) {
      return;
    }

    final first = _viewportPosition(_gesturePointers[0], box);
    final second = _viewportPosition(_gesturePointers[1], box);
    if (first == null || second == null) return;

    final currentFocal = Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
    final currentDistance = math.max((first - second).distance, 1.0);
    final targetScale = (_startScale * (currentDistance / _startDistance))
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();

    var translateX = currentFocal.dx - _startSceneFocal.dx * targetScale;
    var translateY = currentFocal.dy - _startSceneFocal.dy * targetScale;

    // Keep a small part of the document reachable so repeated pans cannot lose
    // the page completely outside the viewport.
    final size = box.size;
    translateX = _clampTranslation(
      translateX,
      viewportExtent: size.width,
      scale: targetScale,
    );
    translateY = _clampTranslation(
      translateY,
      viewportExtent: size.height,
      scale: targetScale,
    );

    controller.value = Matrix4.identity()
      ..translate(translateX, translateY)
      ..scale(targetScale, targetScale);
  }

  double _clampTranslation(
    double translation, {
    required double viewportExtent,
    required double scale,
  }) {
    final scaledExtent = viewportExtent * scale;
    final min = _minimumVisibleExtent - scaledExtent;
    final max = viewportExtent - _minimumVisibleExtent;
    if (min <= max) return translation.clamp(min, max).toDouble();
    return (viewportExtent - scaledExtent) / 2;
  }

  Offset? _viewportPosition(int pointer, RenderBox box) {
    final global = _touchPositions[pointer];
    if (global == null) return null;
    return box.globalToLocal(global);
  }

  void _finishNavigation() {
    if (!_navigating) return;
    _navigating = false;
    _gesturePointers = const <int>[];
    widget.onNavigationChanged?.call(false);

    // Reuse the existing notebook callback so the status bar and +/- zoom
    // controls stay synchronized with a pinch gesture performed here.
    _viewer?.onInteractionEnd?.call(const ScaleEndDetails());
    _viewer = null;
    _viewerBox = null;
  }

  ({InteractiveViewer viewer, RenderBox box})? _findViewerBinding() {
    InteractiveViewer? viewer;
    RenderBox? box;
    context.visitAncestorElements((element) {
      final candidate = element.widget;
      if (candidate is! InteractiveViewer) return true;
      final renderObject = element.findRenderObject();
      if (renderObject is! RenderBox) return false;
      viewer = candidate;
      box = renderObject;
      return false;
    });
    if (viewer == null || box == null || viewer!.transformationController == null) {
      return null;
    }
    return (viewer: viewer!, box: box!);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.active ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
