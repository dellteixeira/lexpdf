import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ink/ink_models.dart';
import 'notebook_object_models.dart';

class NotebookExportPageData {
  const NotebookExportPageData({
    required this.page,
    required this.strokes,
    required this.objects,
  });

  final InkNotebookPage page;
  final List<InkStroke> strokes;
  final List<NotebookObject> objects;
}

class NotebookPdfExporter {
  const NotebookPdfExporter();

  Future<Uint8List> export({
    required String title,
    required List<NotebookExportPageData> pages,
  }) async {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'O caderno precisa ter ao menos uma página.');
    }
    final document = pw.Document(
      title: title,
      creator: 'LexPDF',
      producer: 'LexPDF offline notebook exporter',
    );

    for (final data in pages) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(data.page.width, data.page.height),
          margin: pw.EdgeInsets.zero,
          build: (_) => _buildPage(data),
        ),
      );
    }
    return document.save();
  }

  pw.Widget _buildPage(NotebookExportPageData data) {
    final page = data.page;
    final children = <pw.Widget>[
      pw.CustomPaint(
        size: PdfPoint(page.width, page.height),
        painter: (canvas, size) {
          _paintBackground(canvas, page);
          _paintStrokes(canvas, data.strokes);
          _paintShapeObjects(canvas, data.objects);
        },
      ),
    ];

    for (final object in data.objects) {
      if (object.type == NotebookObjectType.text) {
        children.add(_textObject(object));
      } else if (object.type == NotebookObjectType.image) {
        final image = _imageObject(object);
        if (image != null) children.add(image);
      }
    }
    return pw.Stack(children: children);
  }

  pw.Widget _textObject(NotebookObject object) => pw.Positioned(
        left: object.x,
        top: object.y,
        child: pw.Transform.rotate(
          angle: object.rotation,
          child: pw.SizedBox(
            width: object.width,
            height: object.height,
            child: pw.Text(
              object.textValue ?? '',
              style: pw.TextStyle(
                color: PdfColor.fromInt(object.colorValue),
                fontSize: object.fontSize ?? 20,
              ),
            ),
          ),
        ),
      );

  pw.Widget? _imageObject(NotebookObject object) {
    final path = object.imagePath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) return null;
    return pw.Positioned(
      left: object.x,
      top: object.y,
      child: pw.Transform.rotate(
        angle: object.rotation,
        child: pw.SizedBox(
          width: object.width,
          height: object.height,
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  void _paintBackground(PdfGraphics canvas, InkNotebookPage page) {
    canvas
      ..setFillColor(PdfColors.white)
      ..drawRect(0, 0, page.width, page.height)
      ..fillPath();
    final line = const PdfColor(0.37, 0.42, 0.48, 0.18);
    final accent = const PdfColor(0.37, 0.42, 0.48, 0.30);
    switch (page.background) {
      case InkPageBackground.blank:
        return;
      case InkPageBackground.ruled:
        canvas
          ..setStrokeColor(line)
          ..setLineWidth(1);
        for (double y = 36; y < page.height; y += 36) {
          canvas.drawLine(0, y, page.width, y);
        }
        return;
      case InkPageBackground.grid:
        canvas
          ..setStrokeColor(line)
          ..setLineWidth(1);
        for (double y = 32; y < page.height; y += 32) {
          canvas.drawLine(0, y, page.width, y);
        }
        for (double x = 32; x < page.width; x += 32) {
          canvas.drawLine(x, 0, x, page.height);
        }
        return;
      case InkPageBackground.dotted:
        canvas.setFillColor(const PdfColor(0.37, 0.42, 0.48, 0.25));
        for (double y = 28; y < page.height; y += 28) {
          for (double x = 28; x < page.width; x += 28) {
            canvas
              ..drawEllipse(x, y, 1.15, 1.15)
              ..fillPath();
          }
        }
        return;
      case InkPageBackground.cornell:
        final cueX = page.width * 0.28;
        final summaryY = page.height * 0.82;
        canvas
          ..setStrokeColor(line)
          ..setLineWidth(1);
        for (double y = 36; y < summaryY; y += 36) {
          canvas.drawLine(0, y, page.width, y);
        }
        canvas
          ..setStrokeColor(accent)
          ..setLineWidth(1.3)
          ..drawLine(cueX, 0, cueX, summaryY)
          ..drawLine(0, summaryY, page.width, summaryY);
        return;
      case InkPageBackground.planner:
        const margin = 28.0;
        final header = page.height * 0.12;
        final column = (page.width - margin * 2) / 3;
        canvas
          ..setStrokeColor(accent)
          ..setLineWidth(1.3)
          ..drawRect(margin, margin, page.width - margin * 2, header)
          ..strokePath();
        for (var index = 0; index <= 3; index++) {
          final x = margin + column * index;
          canvas.drawLine(x, margin + header + 16, x, page.height - margin);
        }
        canvas
          ..setStrokeColor(line)
          ..setLineWidth(1);
        for (double y = margin + header + 52; y < page.height - margin; y += 44) {
          canvas.drawLine(margin, y, page.width - margin, y);
        }
        return;
    }
  }

  void _paintStrokes(PdfGraphics canvas, List<InkStroke> strokes) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      canvas
        ..setStrokeColor(PdfColor.fromInt(stroke.colorValue).withAlpha(stroke.opacity))
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);
      for (var index = 1; index < stroke.points.length; index++) {
        final a = stroke.points[index - 1];
        final b = stroke.points[index];
        final pressure = ((a.pressure + b.pressure) / 2).clamp(0.15, 1.0).toDouble();
        final width = stroke.tool == InkTool.highlighter
            ? stroke.width
            : stroke.width * (0.45 + pressure * 0.75);
        canvas
          ..setLineWidth(width)
          ..drawLine(a.x, a.y, b.x, b.y);
      }
    }
  }

  void _paintShapeObjects(PdfGraphics canvas, List<NotebookObject> objects) {
    for (final object in objects) {
      if (object.type == NotebookObjectType.text || object.type == NotebookObjectType.image) {
        continue;
      }
      final color = PdfColor.fromInt(object.colorValue);
      final fill = object.fillColorValue == null ? null : PdfColor.fromInt(object.fillColorValue!);
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(object.strokeWidth)
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);
      final centerX = object.x + object.width / 2;
      final centerY = object.y + object.height / 2;
      PdfPoint p(double x, double y) => _rotatePoint(x, y, centerX, centerY, object.rotation);

      switch (object.type) {
        case NotebookObjectType.line:
        case NotebookObjectType.arrow:
          final a = p(object.x, object.y);
          final b = p(object.x + object.width, object.y + object.height);
          canvas.drawLine(a.x, a.y, b.x, b.y);
          if (object.type == NotebookObjectType.arrow) {
            final angle = math.atan2(b.y - a.y, b.x - a.x);
            const length = 14.0;
            canvas
              ..drawLine(b.x, b.y, b.x - math.cos(angle - math.pi / 6) * length, b.y - math.sin(angle - math.pi / 6) * length)
              ..drawLine(b.x, b.y, b.x - math.cos(angle + math.pi / 6) * length, b.y - math.sin(angle + math.pi / 6) * length);
          }
          break;
        case NotebookObjectType.rectangle:
        case NotebookObjectType.triangle:
          final raw = object.type == NotebookObjectType.rectangle
              ? <PdfPoint>[
                  p(object.x, object.y),
                  p(object.x + object.width, object.y),
                  p(object.x + object.width, object.y + object.height),
                  p(object.x, object.y + object.height),
                ]
              : <PdfPoint>[
                  p(object.x + object.width / 2, object.y),
                  p(object.x + object.width, object.y + object.height),
                  p(object.x, object.y + object.height),
                ];
          canvas.moveTo(raw.first.x, raw.first.y);
          for (final point in raw.skip(1)) {
            canvas.lineTo(point.x, point.y);
          }
          canvas.closePath();
          if (fill != null) {
            canvas
              ..setFillColor(fill)
              ..fillAndStrokePath(close: true);
          } else {
            canvas.strokePath(close: true);
          }
          break;
        case NotebookObjectType.ellipse:
          if (object.rotation == 0) {
            canvas.drawEllipse(centerX, centerY, object.width / 2, object.height / 2);
            if (fill != null) {
              canvas
                ..setFillColor(fill)
                ..fillAndStrokePath(close: true);
            } else {
              canvas.strokePath(close: true);
            }
          } else {
            const segments = 48;
            final points = <PdfPoint>[];
            for (var index = 0; index < segments; index++) {
              final angle = 2 * math.pi * index / segments;
              points.add(p(centerX + math.cos(angle) * object.width / 2, centerY + math.sin(angle) * object.height / 2));
            }
            canvas.moveTo(points.first.x, points.first.y);
            for (final point in points.skip(1)) {
              canvas.lineTo(point.x, point.y);
            }
            canvas.closePath();
            if (fill != null) {
              canvas
                ..setFillColor(fill)
                ..fillAndStrokePath(close: true);
            } else {
              canvas.strokePath(close: true);
            }
          }
          break;
        case NotebookObjectType.text:
        case NotebookObjectType.image:
          break;
      }
    }
  }

  PdfPoint _rotatePoint(
    double x,
    double y,
    double cx,
    double cy,
    double angle,
  ) {
    if (angle == 0) return PdfPoint(x, y);
    final dx = x - cx;
    final dy = y - cy;
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    return PdfPoint(
      cx + dx * cosAngle - dy * sinAngle,
      cy + dx * sinAngle + dy * cosAngle,
    );
  }
}
