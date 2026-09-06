import 'dart:convert';

class SignaturePoint {
  const SignaturePoint(this.x, this.y);

  final double x;
  final double y;

  List<double> toJson() => [x, y];

  static SignaturePoint fromJson(dynamic value) {
    final pair = value as List<dynamic>;
    return SignaturePoint(
      (pair[0] as num).toDouble(),
      (pair[1] as num).toDouble(),
    );
  }
}

class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.name,
    required this.strokes,
    required this.colorValue,
    required this.strokeWidth,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<List<SignaturePoint>> strokes;
  final int colorValue;
  final double strokeWidth;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get strokesJson => encodeStrokes(strokes);

  SavedSignature copyWith({
    String? name,
    int? colorValue,
    double? strokeWidth,
    DateTime? updatedAt,
  }) {
    return SavedSignature(
      id: id,
      name: name ?? this.name,
      strokes: strokes,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  void validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('Signature name cannot be empty.');
    }
    if (strokeWidth <= 0 || !strokeWidth.isFinite) {
      throw ArgumentError.value(strokeWidth, 'strokeWidth', 'Must be > 0');
    }
    if (strokes.isEmpty || strokes.every((stroke) => stroke.length < 2)) {
      throw ArgumentError('Signature must contain at least one drawable stroke.');
    }
    for (final stroke in strokes) {
      for (final point in stroke) {
        if (!point.x.isFinite || !point.y.isFinite ||
            point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) {
          throw ArgumentError('Signature points must use normalized coordinates.');
        }
      }
    }
  }

  static String encodeStrokes(List<List<SignaturePoint>> strokes) {
    return jsonEncode(
      strokes
          .map((stroke) => stroke.map((point) => point.toJson()).toList())
          .toList(),
    );
  }

  static List<List<SignaturePoint>> decodeStrokes(String value) {
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map(
          (stroke) => (stroke as List<dynamic>)
              .map(SignaturePoint.fromJson)
              .toList(growable: false),
        )
        .toList(growable: false);
  }
}
