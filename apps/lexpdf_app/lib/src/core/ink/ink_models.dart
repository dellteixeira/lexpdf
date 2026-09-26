import 'dart:convert';

import 'package:flutter/foundation.dart';

enum InkTool { pen, pencil, highlighter }

enum InkNotebookCover {
  midnight,
  cobalt,
  ocean,
  teal,
  forest,
  sand,
  terracotta,
  coral,
  wine,
  lavender,
  graphite,
  sky;

  String get dbValue => name;

  static InkNotebookCover fromDb(String? value) => switch (value) {
        'cobalt' => InkNotebookCover.cobalt,
        'ocean' => InkNotebookCover.ocean,
        'teal' => InkNotebookCover.teal,
        'forest' => InkNotebookCover.forest,
        'sand' => InkNotebookCover.sand,
        'terracotta' => InkNotebookCover.terracotta,
        'coral' => InkNotebookCover.coral,
        'wine' => InkNotebookCover.wine,
        'lavender' => InkNotebookCover.lavender,
        'graphite' => InkNotebookCover.graphite,
        'sky' => InkNotebookCover.sky,
        _ => InkNotebookCover.midnight,
      };
}

enum InkPageFormat {
  a4Portrait,
  a4Landscape,
  a3Portrait,
  a3Landscape,
  infinite,
  custom;

  String get dbValue => name;

  String get label => switch (this) {
        InkPageFormat.a4Portrait => 'A4 retrato',
        InkPageFormat.a4Landscape => 'A4 paisagem',
        InkPageFormat.a3Portrait => 'A3 retrato',
        InkPageFormat.a3Landscape => 'A3 paisagem',
        InkPageFormat.infinite => 'Infinito',
        InkPageFormat.custom => 'Personalizado',
      };

  double get defaultWidth => switch (this) {
        InkPageFormat.a4Portrait => 794,
        InkPageFormat.a4Landscape => 1123,
        InkPageFormat.a3Portrait => 1123,
        InkPageFormat.a3Landscape => 1587,
        InkPageFormat.infinite => 5200,
        InkPageFormat.custom => 1080,
      };

  double get defaultHeight => switch (this) {
        InkPageFormat.a4Portrait => 1123,
        InkPageFormat.a4Landscape => 794,
        InkPageFormat.a3Portrait => 1587,
        InkPageFormat.a3Landscape => 1123,
        InkPageFormat.infinite => 5200,
        InkPageFormat.custom => 1440,
      };

  static InkPageFormat fromDb(String? value) => switch (value) {
        'a4Portrait' => InkPageFormat.a4Portrait,
        'a4Landscape' => InkPageFormat.a4Landscape,
        'a3Portrait' => InkPageFormat.a3Portrait,
        'a3Landscape' => InkPageFormat.a3Landscape,
        'infinite' => InkPageFormat.infinite,
        _ => InkPageFormat.custom,
      };
}

enum InkPageBackground {
  blank,
  ruled,
  grid,
  dotted,
  cornell,
  planner,
  crossGrid,
  isometric,
  engineering,
  music,
  taskList;

  String get dbValue => name;

  String get label => switch (this) {
        InkPageBackground.blank => 'Em branco',
        InkPageBackground.ruled => 'Pautado',
        InkPageBackground.grid => 'Quadriculado',
        InkPageBackground.dotted => 'Pontilhado',
        InkPageBackground.cornell => 'Cornell',
        InkPageBackground.planner => 'Planner',
        InkPageBackground.crossGrid => 'Grade cruzada',
        InkPageBackground.isometric => 'Isométrico',
        InkPageBackground.engineering => 'Engenharia',
        InkPageBackground.music => 'Partitura',
        InkPageBackground.taskList => 'Lista de tarefas',
      };

  static InkPageBackground fromDb(String value) => switch (value) {
        'ruled' => InkPageBackground.ruled,
        'grid' => InkPageBackground.grid,
        'dotted' => InkPageBackground.dotted,
        'cornell' => InkPageBackground.cornell,
        'planner' => InkPageBackground.planner,
        'crossGrid' => InkPageBackground.crossGrid,
        'isometric' => InkPageBackground.isometric,
        'engineering' => InkPageBackground.engineering,
        'music' => InkPageBackground.music,
        'taskList' => InkPageBackground.taskList,
        _ => InkPageBackground.blank,
      };
}

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
class InkNotebook {
  const InkNotebook({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.cover = InkNotebookCover.midnight,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final InkNotebookCover cover;
}

@immutable
class InkNotebookPage {
  const InkNotebookPage({
    required this.id,
    required this.notebookId,
    required this.pageNumber,
    required this.width,
    required this.height,
    this.background = InkPageBackground.blank,
    this.format = InkPageFormat.custom,
  });

  final String id;
  final String notebookId;
  final int pageNumber;
  final double width;
  final double height;
  final InkPageBackground background;
  final InkPageFormat format;
}
