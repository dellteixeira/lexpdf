import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_pdf_ink_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_reading_progress_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_text_annotation_store.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  const pageCount = 520;
  const documentId = 'acceptance-520';

  test('PDF engine creates and reopens a 520-page document', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-acceptance-pdf');
    addTearDown(() => directory.delete(recursive: true));

    final raster = img.Image(width: 8, height: 8);
    img.fill(raster, color: img.ColorRgb8(255, 255, 255));
    final jpeg = img.encodeJpg(raster, quality: 70);

    final onePage = await PdfDocument.createFromJpegData(
      jpeg,
      width: 595,
      height: 842,
      sourceName: 'acceptance-source.jpg',
    );
    final output = await PdfDocument.createNew(sourceName: 'acceptance-520.pdf');
    try {
      output.pages = List<PdfPage>.generate(
        pageCount,
        (_) => onePage.pages.first,
        growable: false,
      );
      final bytes = await output.encodePdf();
      final path = '${directory.path}${Platform.pathSeparator}acceptance-520.pdf';
      await File(path).writeAsBytes(bytes, flush: true);

      final reopened = await PdfDocument.openFile(path);
      try {
        expect(reopened.pages.length, pageCount);
        expect(reopened.pages.first.pageNumber, 1);
        expect(reopened.pages[259].pageNumber, 260);
        expect(reopened.pages.last.pageNumber, pageCount);
      } finally {
        await reopened.dispose();
      }
    } finally {
      await output.dispose();
      await onePage.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('520-page persistence survives physical database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-acceptance-db');
    addTearDown(() => directory.delete(recursive: true));
    final dbPath = '${directory.path}${Platform.pathSeparator}acceptance.sqlite3';

    var db = LocalDatabase.open(dbPath);
    var catalog = LocalDocumentCatalog(db);
    var progress = LocalReadingProgressStore(db);
    var annotations = LocalTextAnnotationStore(db);
    var ink = LocalPdfInkStore(db);

    await catalog.upsert(
      const DocumentRef(
        id: documentId,
        name: 'acceptance-520.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/acceptance-520.pdf',
        availableOffline: true,
      ),
    );
    db.database.execute(
      'UPDATE documents SET page_count = ? WHERE id = ?;',
      [pageCount, documentId],
    );

    final baseTime = DateTime.utc(2026, 9, 6, 20);
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var page = 1; page <= pageCount; page++) {
        await annotations.upsert(
          LocalTextAnnotation(
            id: 'ann-$page',
            documentId: documentId,
            pageNumber: page,
            startIndex: 0,
            endIndex: 12,
            type: switch (page % 3) {
              0 => TextAnnotationType.highlight,
              1 => TextAnnotationType.underline,
              _ => TextAnnotationType.strikeout,
            },
            selectedText: 'Página $page',
            colorValue: 0xFFFFD54F,
            opacity: page % 3 == 0 ? 0.35 : 1,
            createdAt: baseTime.add(Duration(seconds: page)),
            updatedAt: baseTime.add(Duration(seconds: page)),
          ),
        );
        await ink.addStroke(
          PdfInkStroke(
            id: 'ink-$page',
            documentId: documentId,
            pageNumber: page,
            tool: InkTool.pen,
            colorValue: 0xFF246BFD,
            opacity: 1,
            width: 3,
            points: [
              InkPoint(
                x: 0.1,
                y: 0.1,
                pressure: 0.5,
                tilt: 0.1,
                timestampMicros: page * 1000,
              ),
              InkPoint(
                x: 0.9,
                y: 0.9,
                pressure: 0.8,
                tilt: 0.2,
                timestampMicros: page * 1000 + 500,
              ),
            ],
            createdAt: baseTime.add(Duration(seconds: page)),
          ),
        );
      }
      await progress.save(
        documentId: documentId,
        pageNumber: pageCount,
        zoom: 1.75,
        scrollOffset: 1234.5,
        viewMode: 'continuous',
      );
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }

    expect((await annotations.listForDocument(documentId)).length, pageCount);
    expect((await ink.listForDocument(documentId)).length, pageCount);
    expect((await progress.get(documentId))!.pageNumber, pageCount);
    expect(db.database.select('PRAGMA integrity_check;').single.values.single, 'ok');
    db.close();

    db = LocalDatabase.open(dbPath);
    catalog = LocalDocumentCatalog(db);
    progress = LocalReadingProgressStore(db);
    annotations = LocalTextAnnotationStore(db);
    ink = LocalPdfInkStore(db);
    addTearDown(db.close);

    final reopenedDocument = await catalog.getById(documentId);
    expect(reopenedDocument, isNotNull);
    expect(
      db.database.select('SELECT page_count FROM documents WHERE id = ?;', [documentId]).single['page_count'],
      pageCount,
    );

    final reopenedAnnotations = await annotations.listForDocument(documentId);
    final reopenedInk = await ink.listForDocument(documentId);
    final reopenedProgress = await progress.get(documentId);

    expect(reopenedAnnotations, hasLength(pageCount));
    expect(reopenedAnnotations.first.pageNumber, 1);
    expect(reopenedAnnotations[259].pageNumber, 260);
    expect(reopenedAnnotations.last.pageNumber, pageCount);
    expect(reopenedAnnotations.last.selectedText, 'Página 520');

    expect(reopenedInk, hasLength(pageCount));
    expect(reopenedInk.first.pageNumber, 1);
    expect(reopenedInk[259].pageNumber, 260);
    expect(reopenedInk.last.pageNumber, pageCount);
    expect(reopenedInk.last.points, hasLength(2));
    expect(reopenedInk.last.points.last.pressure, 0.8);

    expect(reopenedProgress, isNotNull);
    expect(reopenedProgress!.pageNumber, pageCount);
    expect(reopenedProgress.zoom, 1.75);
    expect(reopenedProgress.scrollOffset, 1234.5);
    expect(reopenedProgress.viewMode, 'continuous');

    expect(db.database.select('PRAGMA integrity_check;').single.values.single, 'ok');
    expect(db.database.select('PRAGMA foreign_key_check;'), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
