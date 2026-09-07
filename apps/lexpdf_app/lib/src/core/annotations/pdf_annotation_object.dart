enum PdfAnnotationObjectType {
  note,
  text,
  image,
  line,
  arrow,
  rectangle,
  ellipse,
  stamp,
  signature,
}

class PdfAnnotationObject {
  const PdfAnnotationObject({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.colorValue,
    required this.opacity,
    required this.strokeWidth,
    required this.createdAt,
    required this.updatedAt,
    this.fillColorValue,
    this.textValue,
    this.rotation = 0,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final PdfAnnotationObjectType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int colorValue;
  final int? fillColorValue;
  final double opacity;
  final double strokeWidth;
  final String? textValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  PdfAnnotationObject copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? colorValue,
    int? fillColorValue,
    double? opacity,
    double? strokeWidth,
    String? textValue,
    DateTime? updatedAt,
  }) {
    return PdfAnnotationObject(
      id: id,
      documentId: documentId,
      pageNumber: pageNumber,
      type: type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      colorValue: colorValue ?? this.colorValue,
      fillColorValue: fillColorValue ?? this.fillColorValue,
      opacity: opacity ?? this.opacity,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      textValue: textValue ?? this.textValue,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  void validate() {
    if (pageNumber < 1) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'Must be >= 1');
    }
    for (final value in [x, y, width, height]) {
      if (!value.isFinite) throw ArgumentError('Annotation geometry must be finite.');
    }
    if (x < 0 || y < 0 || x > 1 || y > 1 || width < 0 || height < 0) {
      throw ArgumentError('Annotation geometry must use normalized coordinates.');
    }
    if (x + width > 1.000001 || y + height > 1.000001) {
      throw ArgumentError('Annotation bounds must stay inside the page.');
    }
    if (opacity < 0 || opacity > 1) {
      throw ArgumentError.value(opacity, 'opacity', 'Must be between 0 and 1');
    }
    if (strokeWidth <= 0 || !strokeWidth.isFinite) {
      throw ArgumentError.value(strokeWidth, 'strokeWidth', 'Must be > 0');
    }
  }

  static String typeToDb(PdfAnnotationObjectType type) => switch (type) {
        PdfAnnotationObjectType.note => 'note',
        PdfAnnotationObjectType.text => 'text',
        PdfAnnotationObjectType.image => 'image',
        PdfAnnotationObjectType.line => 'line',
        PdfAnnotationObjectType.arrow => 'arrow',
        PdfAnnotationObjectType.rectangle => 'rectangle',
        PdfAnnotationObjectType.ellipse => 'ellipse',
        PdfAnnotationObjectType.stamp => 'stamp',
        PdfAnnotationObjectType.signature => 'signature',
      };

  static PdfAnnotationObjectType typeFromDb(String value) => switch (value) {
        'note' => PdfAnnotationObjectType.note,
        'text' => PdfAnnotationObjectType.text,
        'image' => PdfAnnotationObjectType.image,
        'line' => PdfAnnotationObjectType.line,
        'arrow' => PdfAnnotationObjectType.arrow,
        'rectangle' => PdfAnnotationObjectType.rectangle,
        'ellipse' => PdfAnnotationObjectType.ellipse,
        'stamp' => PdfAnnotationObjectType.stamp,
        'signature' => PdfAnnotationObjectType.signature,
        _ => throw StateError('Unknown PDF annotation object type: $value'),
      };
}
