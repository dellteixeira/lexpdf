import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_android_touch_input_policy.dart';

/// Android pointer router for the PDF workspace.
///
/// The contract is intentionally explicit instead of relying on the gesture
/// arena inside [PdfViewer]:
/// - S Pen / stylus remains available to the active PDF tool;
/// - on active-stylus devices, one touch pointer pans and two touch pointers
///   pan/pinch;
/// - on touch-only Android devices, one touch pointer is reserved for ink when
///   an ink tool is active and navigation starts when a second finger joins;
/// - once touch-ink multi-touch navigation starts it owns the sequence until
///   every finger is lifted;
/// - while a stylus is down, touch contacts are treated as palm input and do
///   not move the document until those contacts are lifted and placed again.
///
/// [PdfViewerParams.panEnabled] and [PdfViewerParams.scaleEnabled] should be
/// disabled on Android while this region is active so the same touch sequence
/// is not applied twice by two independent gesture recognizers.
class PdfAndroidFingerNavigationRegion extends StatefulWidget {
  const PdfAndroidFingerNavigationRegion({
    required this.active,
    required this.controller,
    required this.child,
    this.onFocalPointChanged,
    this.onNavigationChanged,
    this.onNavigationEnd,
    super.key,
  });

  final bool active;
  final PdfViewerController controller;
  final Widget child;
  final ValueChanged<Offset>? onFocalPointChanged;
  final ValueChanged<bool>? onNavigationChanged;
  final VoidCallback? onNavigationEnd;

  @override
  State<PdfAndroidFingerNavigationRegion> createState() =>
      _PdfAndroidFingerNavigationRegionState();
}

class _PdfAndroidFingerNavigationRegionState
    extends State<PdfAndroidFingerNavigationRegion> {
  static const MethodChannel _inputCapabilities = MethodChannel(
    'lexpdf/input_capabilities',
  );

  final Map<int, Offset> _touchPositions = <int, Offset>{};
  final Set<int> _stylusPointers = <int>{};
  final Set<int> _palmBlockedTouches = <int>{};

  bool _navigating = false;
  Offset? _lastFocalPoint;
  double? _lastDistance;

  @override
  void initState() {
    super.initState();
    unawaited(_probeInputCapabilities());
  }

  Future<void> _probeInputCapabilities() async {
    if (!widget.active || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final hasStylus = await _inputCapabilities.invokeMethod<bool>('hasStylus');
      PdfAndroidTouchInputPolicy.setStylusHardwareAvailable(hasStylus);
    } on MissingPluginException {
      // Keep the validated size heuristic as a safe fallback for tests and
      // unusual Android embeddings without the native capability channel.
    } on PlatformException {
      // Capability probing must never block PDF input. Runtime pointer kinds
      // still upgrade the policy when an active stylus is actually used.
    }
  }

  @override
  void didUpdateWidget(covariant PdfAndroidFingerNavigationRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      unawaited(_probeInputCapabilities());
    }
    if (oldWidget.active && !widget.active) {
      _resetTouchState(notifyEnd: true);
    }
  }

  @override
  void dispose() {
    PdfAndroidTouchInputPolicy.reset();
    super.dispose();
  }

  bool _isStylus(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.active) return;

    if (_isStylus(event)) {
      PdfAndroidTouchInputPolicy.registerStylusContact();
      _stylusPointers.add(event.pointer);
      widget.controller.stopInteractiveViewerAnimation();

      // A finger already resting on the display when the S Pen touches down is
      // palm input. Do not let it become navigation immediately after pen-up;
      // require a fresh finger-down event instead.
      _palmBlockedTouches.addAll(_touchPositions.keys);
      _touchPositions.clear();
      PdfAndroidTouchInputPolicy.finishTouchSequence();
      _finishNavigation();
      return;
    }

    if (event.kind != PointerDeviceKind.touch) return;
    if (_stylusPointers.isNotEmpty) {
      _palmBlockedTouches.add(event.pointer);
      return;
    }

    _touchPositions[event.pointer] = event.localPosition;
    widget.controller.stopInteractiveViewerAnimation();

    if (PdfAndroidTouchInputPolicy.compactPhoneInkActive &&
        !PdfAndroidTouchInputPolicy.multiTouchNavigationActive &&
        _touchPositions.length < 2) {
      // A single finger belongs to the active ink tool on touch-only Android
      // devices. Keep tracking its position in case a second finger joins.
      _rebaseGesture();
      return;
    }

    if (PdfAndroidTouchInputPolicy.compactPhoneInkActive &&
        _touchPositions.length >= 2) {
      PdfAndroidTouchInputPolicy.beginMultiTouchNavigation();
    }

    _beginNavigationIfNeeded();
    _rebaseGesture();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.active || event.kind != PointerDeviceKind.touch) return;
    if (_palmBlockedTouches.contains(event.pointer)) return;
    if (!_touchPositions.containsKey(event.pointer)) return;

    _touchPositions[event.pointer] = event.localPosition;
    if (_stylusPointers.isNotEmpty || !widget.controller.isReady) return;

    if (PdfAndroidTouchInputPolicy.compactPhoneInkActive &&
        !PdfAndroidTouchInputPolicy.multiTouchNavigationActive &&
        _touchPositions.length < 2) {
      return;
    }

    if (PdfAndroidTouchInputPolicy.compactPhoneInkActive &&
        _touchPositions.length >= 2 &&
        !PdfAndroidTouchInputPolicy.multiTouchNavigationActive) {
      PdfAndroidTouchInputPolicy.beginMultiTouchNavigation();
      _rebaseGesture();
    }

    _beginNavigationIfNeeded();
    if (!_navigating) return;

    if (_touchPositions.length == 1) {
      _applySingleFingerPan();
    } else {
      _applyTwoFingerPanAndZoom();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isStylus(event)) {
      _stylusPointers.remove(event.pointer);
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;

    _palmBlockedTouches.remove(event.pointer);
    _touchPositions.remove(event.pointer);
    _afterTouchDeparture();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isStylus(event)) {
      _stylusPointers.remove(event.pointer);
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;

    _palmBlockedTouches.remove(event.pointer);
    _touchPositions.remove(event.pointer);
    _afterTouchDeparture();
  }

  void _beginNavigationIfNeeded() {
    if (_navigating || _touchPositions.isEmpty || _stylusPointers.isNotEmpty) {
      return;
    }
    _navigating = true;
    widget.onNavigationChanged?.call(true);
  }

  void _afterTouchDeparture() {
    if (_touchPositions.isEmpty) {
      PdfAndroidTouchInputPolicy.finishTouchSequence();
      _finishNavigation();
      return;
    }
    _rebaseGesture();
  }

  void _rebaseGesture() {
    if (_touchPositions.isEmpty) {
      _lastFocalPoint = null;
      _lastDistance = null;
      return;
    }

    if (_touchPositions.length == 1) {
      _lastFocalPoint = _touchPositions.values.first;
      _lastDistance = null;
      return;
    }

    final pair = _firstTwoTouches();
    _lastFocalPoint = _midpoint(pair.$1, pair.$2);
    _lastDistance = math.max((pair.$1 - pair.$2).distance, 1.0);
  }

  void _applySingleFingerPan() {
    final current = _touchPositions.values.first;
    final previous = _lastFocalPoint;
    _lastFocalPoint = current;
    _lastDistance = null;
    widget.onFocalPointChanged?.call(current);
    if (previous == null) return;

    _panBy(current - previous);
  }

  void _applyTwoFingerPanAndZoom() {
    final pair = _firstTwoTouches();
    final currentFocal = _midpoint(pair.$1, pair.$2);
    final currentDistance = math.max((pair.$1 - pair.$2).distance, 1.0);
    final previousFocal = _lastFocalPoint;
    final previousDistance = _lastDistance;

    widget.onFocalPointChanged?.call(currentFocal);

    if (previousFocal != null) {
      _panBy(currentFocal - previousFocal);
    }

    if (previousDistance != null && previousDistance > 0) {
      final scaleDelta = currentDistance / previousDistance;
      if (scaleDelta.isFinite && (scaleDelta - 1.0).abs() > 0.0001) {
        final controller = widget.controller;
        final targetZoom = (controller.currentZoom * scaleDelta)
            .clamp(controller.minScale, controller.maxScale)
            .toDouble();
        unawaited(
          controller.zoomOnLocalPosition(
            localPosition: currentFocal,
            newZoom: targetZoom,
            duration: Duration.zero,
          ),
        );
      }
    }

    _lastFocalPoint = currentFocal;
    _lastDistance = currentDistance;
  }

  void _panBy(Offset delta) {
    if (!delta.dx.isFinite || !delta.dy.isFinite || delta == Offset.zero) {
      return;
    }
    final controller = widget.controller;
    if (!controller.isReady) return;

    final matrix = controller.value.clone()
      ..translateByDouble(delta.dx, delta.dy, 0, 1);
    controller.value = controller.makeMatrixInSafeRange(
      matrix,
      forceClamp: true,
    );
  }

  (Offset, Offset) _firstTwoTouches() {
    final values = _touchPositions.values.take(2).toList(growable: false);
    return (values[0], values[1]);
  }

  Offset _midpoint(Offset first, Offset second) => Offset(
    (first.dx + second.dx) / 2,
    (first.dy + second.dy) / 2,
  );

  void _finishNavigation() {
    if (!_navigating) {
      _lastFocalPoint = null;
      _lastDistance = null;
      return;
    }
    _navigating = false;
    _lastFocalPoint = null;
    _lastDistance = null;
    widget.onNavigationChanged?.call(false);
    widget.onNavigationEnd?.call();
  }

  void _resetTouchState({required bool notifyEnd}) {
    _touchPositions.clear();
    _stylusPointers.clear();
    _palmBlockedTouches.clear();
    PdfAndroidTouchInputPolicy.finishTouchSequence();
    if (notifyEnd) {
      _finishNavigation();
    } else {
      _navigating = false;
      _lastFocalPoint = null;
      _lastDistance = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.active
          ? HitTestBehavior.opaque
          : HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
