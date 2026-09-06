import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as gen;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../annotations/pdf_annotation_object.dart';
import '../annotations/saved_signature.dart';
import '../ink/pdf_ink_models.dart';
import '../storage/local_pdf_annotation_object_store.dart';
import '../storage/local_pdf_ink_store.dart';
import '../storage/local_text_annotation_store.dart';

class LexPdfExportService {
  const LexPdfExportService({
    required this.textStore,
    required this.inkStore,
    required this.objectStore,
  });

  final LocalTextAnnotationStore textStore;
  final LocalPdfInkStore inkStore;
  final LocalPdfAnnotationObjectStore objectStore;

  Future<Uint8List> exportEditableBundle({
    required String documentId,
    required String sourcePath,
  }) async {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final text = await textStore.listForDocument(documentId);
    final ink = await inkStore.listForDocument(documentId);
    final objects = await objectStore.listForDocument(documentId);
    final payload = <String, dynamic>{
      'format': 'lexpdf-editable',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'sourcePdfBase64': base64Encode(sourceBytes),
      'layers': {
        'textAnnotations': text.map(_textToJson).toList(growable: false),
        'ink': ink.map(_inkToJson).toList(growable: false),
        'objects': objects.map(_objectToJson).toList(growable: false),
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  Future<Uint8List> exportFlattenedPdf({
    required String documentId,
    required String sourcePath,
    double renderScale = 1.5,
  }) async {
    final source = await PdfDocument.openFile(sourcePath);
    final output = pw.Document();
    final allText = await textStore.listForDocument(documentId);
    final allInk = await inkStore.listForDocument(documentId);
    final allObjects = await objectStore.listForDocument(documentId);
    try {
      for (final page in source.pages) {
        final render = await page.render(
          width: math.max(1, (page.width * renderScale).round()),
          height: math.max(1, (page.height * renderScale).round()),
          backgroundColor: 0xFFFFFFFF,
          annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
        );
        if (render == null) {
          throw StateError('Não foi possível renderizar a página ${page.pageNumber}.');
        }
        late final Uint8List pngBytes;
        try {
          pngBytes = Uint8List.fromList(img.encodePng(render.createImageNF()));
        } finally {
          render.dispose();
        }
        final base = pw.MemoryImage(pngBytes);
        final pageTextAnnotations = allText
            .where((item) => item.pageNumber == page.pageNumber)
            .toList(growable: false);
        final pageInk = allInk
            .where((item) => item.pageNumber == page.pageNumber)
            .toList(growable: false);
        final pageObjects = allObjects
            .where((item) => item.pageNumber == page.pageNumber)
            .toList(growable: false);
        final textRects = await _resolveTextRects(page, pageTextAnnotations);

        output.addPage(
          pw.Page(
            pageFormat: gen.PdfPageFormat(page.width, page.height, marginAll: 0),
            build: (_) => pw.Stack(
              children: [
                pw.Image(
                  base,
                  width: page.width,
                  height: page.height,
                  fit: pw.BoxFit.fill,
                ),
                pw.CustomPaint(
                  size: gen.PdfPoint(page.width, page.height),
                  painter: (canvas, size) {
                    _paintTextMarkup(canvas, textRects);
                    _paintInk(canvas, pageInk, page.width, page.height);
                    _paintObjectShapes(canvas, pageObjects, page.width, page.height);
                  },
                ),
                ..._objectTextWidgets(pageObjects, page.width, page.height),
              ],
            ),
          ),
        );
      }
      return await output.save();
    } finally {
      await source.dispose();
    }
  }

  Future<List<_ResolvedTextMarkup>> _resolveTextRects(
    PdfPage page,
    List<LocalTextAnnotation> annotations,
  ) async {
    if (annotations.isEmpty) return const [];
    final structured = await page.loadStructuredText();
    final resolved = <_ResolvedTextMarkup>[];
    for (final annotation in annotations) {
      if (annotation.startIndex < 0 ||
          annotation.endIndex > structured.fullText.length ||
          annotation.endIndex < annotation.startIndex) {
        continue;
      }
      final range = PdfPageTextRange(
        pageText: structured,
        start: annotation.startIndex,
        end: annotation.endIndex,
      );
      for (final fragment in range.enumerateFragmentBoundingRects()) {
        resolved.add(
          _ResolvedTextMarkup(annotation: annotation, rect: fragment.bounds),
        );
      }
    }
    return resolved;
  }

  void _paintTextMarkup(
    gen.PdfGraphics canvas,
    List<_ResolvedTextMarkup> markups,
  ) {
    for (final item in markups) {
      final color = gen.PdfColor.fromInt(item.annotation.colorValue);
      final rect = item.rect;
      canvas.saveContext();
      canvas.setGraphicState(
        gen.PdfGraphicState(
          strokeOpacity: item.annotation.opacity,
          fillOpacity: item.annotation.opacity,
        ),
      );
      switch (item.annotation.type) {
        case TextAnnotationType.highlight:
          canvas.setFillColor(color);
          canvas.drawRect(rect.left, rect.bottom, rect.width, rect.height);
          canvas.fillPath();
        case TextAnnotationType.underline:
          canvas.setStrokeColor(color);
          canvas.setLineWidth(math.max(1, rect.height * 0.08));
          canvas.drawLine(rect.left, rect.bottom, rect.right, rect.bottom);
        case TextAnnotationType.strikeout:
          canvas.setStrokeColor(color);
          canvas.setLineWidth(math.max(1, rect.height * 0.08));
          final y = rect.bottom + rect.height * 0.5;
          canvas.drawLine(rect.left, y, rect.right, y);
      }
      canvas.restoreContext();
    }
  }

  void _paintInk(
    gen.PdfGraphics canvas,
    List<PdfInkStroke> strokes,
    double pageWidth,
    double pageHeight,
  ) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      canvas.saveContext();
      canvas.setStrokeColor(gen.PdfColor.fromInt(stroke.colorValue));
      canvas.setLineWidth(stroke.width);
      canvas.setLineCap(gen.PdfLineCap.round);
      canvas.setLineJoin(gen.PdfLineJoin.round);
      canvas.setGraphicState(gen.PdfGraphicState(strokeOpacity: stroke.opacity));
      final first = stroke.points.first;
      canvas.moveTo(first.x * pageWidth, pageHeight - first.y * pageHeight);
      for (final point in stroke.points.skip(1)) {
        canvas.lineTo(point.x * pageWidth, pageHeight - point.y * pageHeight);
      }
      canvas.strokePath();
      canvas.restoreContext();
    }
  }

  void _paintObjectShapes(
    gen.PdfGraphics canvas,
    List<PdfAnnotationObject> objects,
    double pageWidth,
    double pageHeight,
  ) {
    for (final object in objects) {
      final x = object.x * pageWidth;
      final yTop = object.y * pageHeight;
      final width = object.width * pageWidth;
      final height = object.height * pageHeight;
      final y = pageHeight - yTop - height;
      final color = gen.PdfColor.fromInt(object.colorValue);
      canvas.saveContext();
      canvas.setStrokeColor(color);
      canvas.setLineWidth(object.strokeWidth);
      canvas.setGraphicState(
        gen.PdfGraphicState(
          strokeOpacity: object.opacity,
          fillOpacity: object.opacity,
        ),
      );
      switch (object.type) {
        case PdfAnnotationObjectType.line:
          canvas.drawLine(x, y + height, x + width, y);
        case PdfAnnotationObjectType.arrow:
          canvas.drawLine(x, y + height, x + width, y);
          final angle = math.atan2(-height, width);
          final endX = x + width;
          final endY = y;
          final length = math.max(8.0, object.strokeWidth * 4);
          canvas.drawLine(
            endX,
            endY,
            endX - math.cos(angle - 0.55) * length,
            endY - math.sin(angle - 0.55) * length,
          );
          canvas.drawLine(
            endX,
            endY,
            endX - math.cos(angle + 0.55) * length,
            endY - math.sin(angle + 0.55) * length,
          );
        case PdfAnnotationObjectType.rectangle:
          canvas.drawRect(x, y, width, height);
          canvas.strokePath();
        case PdfAnnotationObjectType.ellipse:
          canvas.drawEllipse(x + width / 2, y + height / 2, width / 2, height / 2);
          canvas.strokePath();
        case PdfAnnotationObjectType.signature:
          _paintSignature(canvas, object, x, y, width, height);
        case PdfAnnotationObjectType.note ||
              PdfAnnotationObjectType.text ||
              PdfAnnotationObjectType.stamp:
          break;
      }
      canvas.restoreContext();
    }
  }

  void _paintSignature(
    gen.PdfGraphics canvas,
    PdfAnnotationObject object,
    double x,
    double y,
    double width,
    double height,
  ) {
    final data = object.textValue;
    if (data == null || data.isEmpty) return;
    List<List<SignaturePoint>> strokes;
    try {
      strokes = SavedSignature.decodeStrokes(data);
    } catch (_) {
      return;
    }
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final first = stroke.first;
      canvas.moveTo(x + first.x * width, y + (1 - first.y) * height);
      for (final point in stroke.skip(1)) {
        canvas.lineTo(x + point.x * width, y + (1 - point.y) * height);
      }
      canvas.strokePath();
    }
  }

  List<pw.Widget> _objectTextWidgets(
    List<PdfAnnotationObject> objects,
    double pageWidth,
    double pageHeight,
  ) {
    final widgets = <pw.Widget>[];
    for (final object in objects) {
      if (object.type == PdfAnnotationObjectType.signature) continue;
      final text = object.textValue;
      if (text == null || text.isEmpty) continue;
      if (object.type != PdfAnnotationObjectType.note &&
          object.type != PdfAnnotationObjectType.text &&
          object.type != PdfAnnotationObjectType.stamp) {
        continue;
      }
      final color = gen.PdfColor.fromInt(object.colorValue);
      final background = object.type == PdfAnnotationObjectType.note
          ? gen.PdfColor.fromInt(object.fillColorValue ?? 0xFFFFF59D)
          : null;
      widgets.add(
        pw.Positioned(
          left: object.x * pageWidth,
          top: object.y * pageHeight,
          width: object.width * pageWidth,
          height: object.height * pageHeight,
          child: pw.Container(
            padding: object.type == PdfAnnotationObjectType.note
                ? const pw.EdgeInsets.all(4)
                : pw.EdgeInsets.zero,
            color: background,
            decoration: object.type == PdfAnnotationObjectType.stamp
                ? pw.BoxDecoration(
                    border: pw.Border.all(color: color, width: object.strokeWidth),
                  )
                : null,
            child: pw.Center(
              child: pw.Text(
                text,
                maxLines: 5,
                style: pw.TextStyle(
                  color: color,
                  fontSize: object.type == PdfAnnotationObjectType.stamp ? 13 : 11,
                  fontWeight: object.type == PdfAnnotationObjectType.stamp
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Map<String, dynamic> _textToJson(LocalTextAnnotation value) => {
        'id': value.id,
        'documentId': value.documentId,
        'pageNumber': value.pageNumber,
        'startIndex': value.startIndex,
        'endIndex': value.endIndex,
        'type': value.type.name,
        'selectedText': value.selectedText,
        'colorValue': value.colorValue,
        'opacity': value.opacity,
        'createdAt': value.createdAt.toUtc().toIso8601String(),
        'updatedAt': value.updatedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _inkToJson(PdfInkStroke value) => {
        'id': value.id,
        'documentId': value.documentId,
        'pageNumber': value.pageNumber,
        'tool': value.tool.name,
        'colorValue': value.colorValue,
        'opacity': value.opacity,
        'width': value.width,
        'points': value.points
            .map((point) => {
                  'x': point.x,
                  'y': point.y,
                  'pressure': point.pressure,
                  'tilt': point.tilt,
                  'timestampMicros': point.timestampMicros,
                })
            .toList(growable: false),
        'createdAt': value.createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _objectToJson(PdfAnnotationObject value) => {
        'id': value.id,
        'documentId': value.documentId,
        'pageNumber': value.pageNumber,
        'type': value.type.name,
        'x': value.x,
        'y': value.y,
        'width': value.width,
        'height': value.height,
        'rotation': value.rotation,
        'colorValue': value.colorValue,
        'fillColorValue': value.fillColorValue,
        'opacity': value.opacity,
        'strokeWidth': value.strokeWidth,
        'textValue': value.textValue,
        'createdAt': value.createdAt.toUtc().toIso8601String(),
        'updatedAt': value.updatedAt.toUtc().toIso8601String(),
      };
}

class _ResolvedTextMarkup {
  const _ResolvedTextMarkup({required this.annotation, required this.rect});
  final LocalTextAnnotation annotation;
  final PdfRect rect;
}
