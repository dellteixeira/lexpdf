import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/notebook/notebook_object_models.dart';
import 'package:lexxpdf_app/src/core/notebook/notebook_pdf_exporter.dart';

void main() {
  test('exports a notebook page as a valid PDF with vector content', () async {
    final page = InkNotebookPage(
      id: 'page-1',
      notebookId: 'notebook-1',
      pageNumber: 1,
      width: 540,
      height: 720,
      background: InkPageBackground.grid,
    );
    final stroke = InkStroke(
      id: 'stroke-1',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 3,
      points: const [
        InkPoint(x: 20, y: 30, pressure: 0.4, tilt: 0, timestampMicros: 1),
        InkPoint(x: 80, y: 90, pressure: 0.9, tilt: 0.1, timestampMicros: 2),
      ],
      createdAt: DateTime.utc(2026, 9, 6),
    );
    final object = NotebookObject(
      id: 'object-1',
      pageId: page.id,
      type: NotebookObjectType.rectangle,
      x: 100,
      y: 100,
      width: 120,
      height: 80,
      rotation: 0.2,
      colorValue: 0xFFD32F2F,
      fillColorValue: 0x22D32F2F,
      strokeWidth: 2,
      createdAt: DateTime.utc(2026, 9, 6),
      updatedAt: DateTime.utc(2026, 9, 6),
    );

    final bytes = await const NotebookPdfExporter().export(
      title: 'Teste',
      pages: [NotebookExportPageData(page: page, strokes: [stroke], objects: [object])],
    );

    expect(bytes.length, greaterThan(500));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('exports multiple notebook pages into one PDF document', () async {
    final pages = List.generate(
      3,
      (index) => NotebookExportPageData(
        page: InkNotebookPage(
          id: 'page-${index + 1}',
          notebookId: 'notebook-1',
          pageNumber: index + 1,
          width: 540,
          height: 720,
          background: InkPageBackground.values[index],
        ),
        strokes: const [],
        objects: const [],
      ),
    );

    final bytes = await const NotebookPdfExporter().export(
      title: 'Caderno inteiro',
      pages: pages,
    );

    expect(bytes.length, greaterThan(700));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('rejects export without pages', () async {
    await expectLater(
      const NotebookPdfExporter().export(title: 'Vazio', pages: const []),
      throwsArgumentError,
    );
  });
}
