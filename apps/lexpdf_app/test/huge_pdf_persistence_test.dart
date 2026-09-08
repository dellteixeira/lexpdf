import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_ink_store.dart';
import 'package:lexpdf_app/src/core/storage/local_reading_progress_store.dart';
import 'package:lexpdf_app/src/core/storage/local_text_annotation_store.dart';

void main() {
  test('2500-page document overlays can be queried in a fixed-size window', () async {
    const pageCount = 2500;
    const documentId = 'huge-2500';
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final catalog = LocalDocumentCatalog(db);
    final annotations = LocalTextAnnotationStore(db);
    final ink = LocalPdfInkStore(db);

    await catalog.upsert(
      const DocumentRef(
        id: documentId,
        name: 'huge-2500.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/huge-2500.pdf',
        availableOffline: true,
      ),
    );

    final base = DateTime.utc(2026, 9, 7);
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var page = 1; page <= pageCount; page++) {
        await annotations.upsert(
          LocalTextAnnotation(
            id: 'a-$page',
            documentId: documentId,
            pageNumber: page,
            startIndex: 0,
            endIndex: 4,
            type: TextAnnotationType.highlight,
            selectedText: 'p$page',
            colorValue: 0xFFFFD54F,
            opacity: 0.35,
            createdAt: base.add(Duration(seconds: page)),
            updatedAt: base.add(Duration(seconds: page)),
          ),
        );
        await ink.addStroke(
          PdfInkStroke(
            id: 'i-$page',
            documentId: documentId,
            pageNumber: page,
            tool: InkTool.pen,
            colorValue: 0xFF246BFD,
            opacity: 1,
            width: 2,
            points: [
              InkPoint(
                x: 0.1,
                y: 0.1,
                pressure: 0.5,
                tilt: 0,
                timestampMicros: page,
              ),
              InkPoint(
                x: 0.2,
                y: 0.2,
                pressure: 0.5,
                tilt: 0,
                timestampMicros: page + 1,
              ),
            ],
            createdAt: base.add(Duration(seconds: page)),
          ),
        );
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }

    expect(await annotations.countForDocument(documentId), pageCount);
    expect(await ink.countForDocument(documentId), pageCount);

    final annotationWindow =
        await annotations.listForPageRange(documentId, 1248, 1253);
    final inkWindow = await ink.listForPageRange(documentId, 1248, 1253);

    expect(annotationWindow, hasLength(6));
    expect(inkWindow, hasLength(6));
    expect(annotationWindow.first.pageNumber, 1248);
    expect(annotationWindow.last.pageNumber, 1253);
    expect(inkWindow.first.pageNumber, 1248);
    expect(inkWindow.last.pageNumber, 1253);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('5000-page reading state and distant overlays survive close and reopen', () async {
    const documentId = 'huge-5000-reopen';
    const distantPages = <int>[
      1,
      2,
      3,
      997,
      998,
      999,
      2498,
      2499,
      2500,
      4998,
      4999,
      5000,
    ];

    final directory =
        await Directory.systemTemp.createTemp('lexpdf-huge-persistence');
    addTearDown(() => directory.delete(recursive: true));
    final dbPath =
        '${directory.path}${Platform.pathSeparator}lexpdf-huge.sqlite';

    final firstDb = LocalDatabase.open(dbPath);
    final firstCatalog = LocalDocumentCatalog(firstDb);
    final firstAnnotations = LocalTextAnnotationStore(firstDb);
    final firstInk = LocalPdfInkStore(firstDb);
    final firstProgress = LocalReadingProgressStore(firstDb);

    await firstCatalog.upsert(
      const DocumentRef(
        id: documentId,
        name: 'huge-5000.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/huge-5000.pdf',
        availableOffline: true,
      ),
    );

    final base = DateTime.utc(2026, 9, 8);
    for (final page in distantPages) {
      await firstAnnotations.upsert(
        LocalTextAnnotation(
          id: 'reopen-a-$page',
          documentId: documentId,
          pageNumber: page,
          startIndex: 0,
          endIndex: 4,
          type: TextAnnotationType.highlight,
          selectedText: 'p$page',
          colorValue: 0xFFFFD54F,
          opacity: 0.35,
          createdAt: base.add(Duration(seconds: page)),
          updatedAt: base.add(Duration(seconds: page)),
        ),
      );
      await firstInk.addStroke(
        PdfInkStroke(
          id: 'reopen-i-$page',
          documentId: documentId,
          pageNumber: page,
          tool: InkTool.pen,
          colorValue: 0xFF246BFD,
          opacity: 1,
          width: 2,
          points: [
            InkPoint(
              x: 0.1,
              y: 0.1,
              pressure: 0.5,
              tilt: 0,
              timestampMicros: page,
            ),
            InkPoint(
              x: 0.2,
              y: 0.2,
              pressure: 0.5,
              tilt: 0,
              timestampMicros: page + 1,
            ),
          ],
          createdAt: base.add(Duration(seconds: page)),
        ),
      );
    }
    await firstProgress.save(documentId: documentId, pageNumber: 5000);
    firstDb.close();

    expect(File(dbPath).existsSync(), isTrue);
    expect(File(dbPath).lengthSync(), greaterThan(0));

    final reopenedDb = LocalDatabase.open(dbPath);
    addTearDown(reopenedDb.close);
    final reopenedAnnotations = LocalTextAnnotationStore(reopenedDb);
    final reopenedInk = LocalPdfInkStore(reopenedDb);
    final reopenedProgress = LocalReadingProgressStore(reopenedDb);

    expect(await reopenedAnnotations.countForDocument(documentId), distantPages.length);
    expect(await reopenedInk.countForDocument(documentId), distantPages.length);
    expect((await reopenedProgress.get(documentId))?.pageNumber, 5000);

    final middleAnnotations =
        await reopenedAnnotations.listForPageRange(documentId, 2498, 2503);
    final middleInk = await reopenedInk.listForPageRange(documentId, 2498, 2503);
    expect(middleAnnotations.map((item) => item.pageNumber), [2498, 2499, 2500]);
    expect(middleInk.map((item) => item.pageNumber), [2498, 2499, 2500]);

    final finalAnnotations =
        await reopenedAnnotations.listForPageRange(documentId, 4998, 5000);
    final finalInk = await reopenedInk.listForPageRange(documentId, 4998, 5000);
    expect(finalAnnotations.map((item) => item.pageNumber), [4998, 4999, 5000]);
    expect(finalInk.map((item) => item.pageNumber), [4998, 4999, 5000]);
  });
}
