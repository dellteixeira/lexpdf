import 'package:flutter/foundation.dart';

enum NotebookPaperSize {
  a4,
  a3,
  letter,
  square,
  infinite;

  String get label => switch (this) {
        NotebookPaperSize.a4 => 'A4',
        NotebookPaperSize.a3 => 'A3',
        NotebookPaperSize.letter => 'Carta',
        NotebookPaperSize.square => 'Quadrado',
        NotebookPaperSize.infinite => 'Infinito',
      };

  double get width => switch (this) {
        NotebookPaperSize.a4 => 794,
        NotebookPaperSize.a3 => 1123,
        NotebookPaperSize.letter => 816,
        NotebookPaperSize.square => 1200,
        NotebookPaperSize.infinite => 6000,
      };

  double get height => switch (this) {
        NotebookPaperSize.a4 => 1123,
        NotebookPaperSize.a3 => 1587,
        NotebookPaperSize.letter => 1056,
        NotebookPaperSize.square => 1200,
        NotebookPaperSize.infinite => 6000,
      };

  bool get isInfinite => this == NotebookPaperSize.infinite;

  static NotebookPaperSize infer(double width, double height) {
    if (width >= 5000 || height >= 5000) return NotebookPaperSize.infinite;
    if ((width - 1123).abs() < 8 && (height - 1587).abs() < 8) {
      return NotebookPaperSize.a3;
    }
    if ((width - 816).abs() < 8 && (height - 1056).abs() < 8) {
      return NotebookPaperSize.letter;
    }
    if ((width - height).abs() < 8) return NotebookPaperSize.square;
    return NotebookPaperSize.a4;
  }
}

@immutable
class NotebookPaperPreset {
  const NotebookPaperPreset({
    required this.size,
    this.landscape = false,
  });

  final NotebookPaperSize size;
  final bool landscape;

  double get width => landscape && !size.isInfinite ? size.height : size.width;
  double get height => landscape && !size.isInfinite ? size.width : size.height;

  String get label {
    if (size.isInfinite || size == NotebookPaperSize.square) return size.label;
    return '${size.label} ${landscape ? 'paisagem' : 'retrato'}';
  }
}
