import 'dart:convert';

import 'package:flutter/foundation.dart';

enum InkTool { pen, pencil, highlighter }

@immutable
class InkPoint {
  const InkPoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tilt,
    required this.timestampMicros,
  });

  final double x;
  final double y;
  final double pressure;
  final double tilt;
  final int timestampMicros;

  Map<String, Object> toJson() => {
        'x': x,
        'y': y,
        'pressure': pressure,
        'tilt': tilt,
        'timestampMicros': timestampMicros,
      };

  factory InkPoint.fromJson(Map<String, Object?> json) => InkPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['pressure'] as num).toDouble(),
        tilt: (json['tilt'] as num).toDouble(),
        timestampMicros: (json['timestampMicros'] as num).toInt(),
      );
}

@immutable
class InkStroke {
  const InkStroke({
    required this.id,
    required this.pageId,
    required this.tool,
    required this.colorValue,
    required this.opacity,
    required this.width,
    required this.points,
    required this.createdAt,
  });

  final String id;
  final String pageId;
  final InkTool tool;
  final int colorValue;
  final double opacity;
  final double width;
  final List<InkPoint> points;
  final DateTime createdAt;

  String encodePoints() => jsonEncode(points.map((point) => point.toJson()).toList());

  static List<InkPoint> decodePoints(String value) {
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map((item) => InkPoint.fromJson((item as Map).cast<String, Object?>()))
        .toList(growable: false);
  }
}

@immutable
class InkNotebookPage {
  const InkNotebookPage({
    required this.id,
    required this.notebookId,
    required this.pageNumber,
    required this.width,
    required this.height,
  });

  final String id;
  final String notebookId;
  final int pageNumber;
  final double width;
  final double height;
}
