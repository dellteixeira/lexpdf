import 'dart:math' as math;

import 'ink_models.dart';
import 'pdf_ink_models.dart';

class PdfInkEraseResult {
  const PdfInkEraseResult({
    required this.original,
    required this.fragments,
  });

  final PdfInkStroke original;
  final List<PdfInkStroke> fragments;
}

class PdfInkEraser {
  const PdfInkEraser();

  PdfInkEraseResult? eraseAt({
    required PdfInkStroke stroke,
    required double localX,
    required double localY,
    required double pageWidth,
    required double pageHeight,
    required double radius,
  }) {
    if (stroke.points.length < 2 ||
        pageWidth <= 0 ||
        pageHeight <= 0 ||
        radius <= 0) {
      return null;
    }

    final fragments = <List<InkPoint>>[];
    var current = <InkPoint>[];
    var touched = false;

    void append(InkPoint point) {
      if (current.isNotEmpty && _samePoint(current.last, point)) return;
      current.add(point);
    }

    void flush() {
      if (current.length >= 2) {
        fragments.add(List<InkPoint>.unmodifiable(current));
      }
      current = <InkPoint>[];
    }

    for (var index = 1; index < stroke.points.length; index++) {
      final a = stroke.points[index - 1];
      final b = stroke.points[index];
      final intervals = _outsideIntervals(
        a: a,
        b: b,
        localX: localX,
        localY: localY,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        radius: radius,
      );

      if (intervals.length != 1 ||
          intervals.first.$1 > 1e-9 ||
          intervals.first.$2 < 1 - 1e-9) {
        touched = true;
      }

      if (intervals.isEmpty) {
        flush();
        continue;
      }

      for (var intervalIndex = 0;
          intervalIndex < intervals.length;
          intervalIndex++) {
        final interval = intervals[intervalIndex];
        final start = _interpolate(a, b, interval.$1);
        final end = _interpolate(a, b, interval.$2);

        if (current.isNotEmpty && !_samePoint(current.last, start)) {
          flush();
        }
        append(start);
        append(end);

        if (intervalIndex < intervals.length - 1 || interval.$2 < 1 - 1e-9) {
          flush();
        }
      }
    }
    flush();

    if (!touched) return null;

    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final resultFragments = <PdfInkStroke>[];
    for (var index = 0; index < fragments.length; index++) {
      resultFragments.add(
        PdfInkStroke(
          id: '${stroke.id}-e-$stamp-$index',
          documentId: stroke.documentId,
          pageNumber: stroke.pageNumber,
          tool: stroke.tool,
          colorValue: stroke.colorValue,
          opacity: stroke.opacity,
          width: stroke.width,
          points: fragments[index],
          createdAt: stroke.createdAt,
        ),
      );
    }

    return PdfInkEraseResult(
      original: stroke,
      fragments: List<PdfInkStroke>.unmodifiable(resultFragments),
    );
  }

  List<(double, double)> _outsideIntervals({
    required InkPoint a,
    required InkPoint b,
    required double localX,
    required double localY,
    required double pageWidth,
    required double pageHeight,
    required double radius,
  }) {
    final ax = a.x * pageWidth - localX;
    final ay = a.y * pageHeight - localY;
    final bx = b.x * pageWidth - localX;
    final by = b.y * pageHeight - localY;
    final dx = bx - ax;
    final dy = by - ay;
    final qa = dx * dx + dy * dy;

    if (qa <= 1e-18) {
      final outside = ax * ax + ay * ay > radius * radius;
      return outside ? const [(0.0, 1.0)] : const [];
    }

    final qb = 2 * (ax * dx + ay * dy);
    final qc = ax * ax + ay * ay - radius * radius;
    final discriminant = qb * qb - 4 * qa * qc;
    final cuts = <double>[0, 1];

    if (discriminant >= 0) {
      final root = math.sqrt(discriminant);
      final t1 = (-qb - root) / (2 * qa);
      final t2 = (-qb + root) / (2 * qa);
      if (t1 > 1e-9 && t1 < 1 - 1e-9) cuts.add(t1);
      if (t2 > 1e-9 && t2 < 1 - 1e-9) cuts.add(t2);
    }

    cuts.sort();
    final unique = <double>[];
    for (final value in cuts) {
      if (unique.isEmpty || (value - unique.last).abs() > 1e-9) {
        unique.add(value);
      }
    }

    final outside = <(double, double)>[];
    for (var index = 1; index < unique.length; index++) {
      final start = unique[index - 1];
      final end = unique[index];
      final mid = (start + end) / 2;
      final mx = ax + dx * mid;
      final my = ay + dy * mid;
      if (mx * mx + my * my > radius * radius + 1e-9) {
        outside.add((start, end));
      }
    }
    return outside;
  }

  InkPoint _interpolate(InkPoint a, InkPoint b, double t) {
    if (t <= 1e-9) return a;
    if (t >= 1 - 1e-9) return b;
    return InkPoint(
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      pressure: a.pressure + (b.pressure - a.pressure) * t,
      tilt: a.tilt + (b.tilt - a.tilt) * t,
      timestampMicros: (a.timestampMicros +
              (b.timestampMicros - a.timestampMicros) * t)
          .round(),
    );
  }

  bool _samePoint(InkPoint a, InkPoint b) =>
      (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;
}
