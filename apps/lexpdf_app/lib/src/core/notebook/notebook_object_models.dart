import 'package:flutter/foundation.dart';

enum NotebookObjectType {
  line,
  arrow,
  rectangle,
  ellipse,
  triangle,
  text,
  image;

  String get dbValue => name;

  static NotebookObjectType fromDb(String value) => switch (value) {
        'line' => NotebookObjectType.line,
        'arrow' => NotebookObjectType.arrow,
        'rectangle' => NotebookObjectType.rectangle,
        'ellipse' => NotebookObjectType.ellipse,
        'triangle' => NotebookObjectType.triangle,
        'text' => NotebookObjectType.text,
        'image' => NotebookObjectType.image,
        _ => throw StateError('Tipo de objeto de caderno desconhecido: $value'),
      };
}

@immutable
class NotebookObject {
  const NotebookObject({
    required this.id,
    required this.pageId,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
    required this.colorValue,
    required this.strokeWidth,
    required this.createdAt,
    required this.updatedAt,
    this.fillColorValue,
    this.textValue,
    this.fontSize,
    this.imagePath,
  });

  final String id;
  final String pageId;
  final NotebookObjectType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int colorValue;
  final int? fillColorValue;
  final double strokeWidth;
  final String? textValue;
  final double? fontSize;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotebookObject copyWith({
    String? id,
    String? pageId,
    NotebookObjectType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? colorValue,
    int? fillColorValue,
    bool clearFillColor = false,
    double? strokeWidth,
    String? textValue,
    double? fontSize,
    String? imagePath,
    DateTime? updatedAt,
  }) {
    return NotebookObject(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      colorValue: colorValue ?? this.colorValue,
      fillColorValue: clearFillColor ? null : (fillColorValue ?? this.fillColorValue),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      textValue: textValue ?? this.textValue,
      fontSize: fontSize ?? this.fontSize,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
