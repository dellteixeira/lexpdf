import 'package:flutter/foundation.dart';

import 'ink_models.dart';

@immutable
class PdfInkStroke {
  const PdfInkStroke({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.tool,
    required this.colorValue,
    required this.opacity,
    required this.width,
    required this.points,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final InkTool tool;
  final int colorValue;
  final double opacity;
  final double width;

  /// Pontos normalizados no espaço da página (0..1 em X/Y).
  final List<InkPoint> points;
  final DateTime createdAt;

  String encodePoints() => InkStroke(
        id: id,
        pageId: 'pdf:$documentId:$pageNumber',
        tool: tool,
        colorValue: colorValue,
        opacity: opacity,
        width: width,
        points: points,
        createdAt: createdAt,
      ).encodePoints();
}
