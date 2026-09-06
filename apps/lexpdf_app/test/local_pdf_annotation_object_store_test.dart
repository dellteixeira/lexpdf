import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/annotations/pdf_annotation_object.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_pdf_annotation_object_store.dart';

void main() {
  Future<(LocalDatabase, LocalPdfAnnotationObjectStore)> setup() async {
    final db = LocalDatabase.inMemory();
    final catalog = LocalDocumentCatalog(db);
    await catalog.upsert(
      const DocumentRef(
        id: 'doc-annotations',
        provider: DocumentProviderKind.local,
        name: 'anotacoes.pdf',
        localPath: '/tmp/anotacoes.pdf',
        availableOffline: true,
        syncState: DocumentSyncState.localOnly,
      ),
    );
    return (db, LocalPdfAnnotationObjectStore(db));
  }

  PdfAnnotationObject object(PdfAnnotationObjectType type, {String? text}) {
    final now = DateTime.utc(2026, 9, 6);
    return PdfAnnotationObject(
      id: 'object-${type.name}',
      documentId: 'doc-annotations',
      pageNumber: 2,
      type: type,
      x: 0.1,
      y: 0.2,
      width: 0.3,
      height: 0.1,
      colorValue: 0xFF246BFD,
      opacity: 0.9,
      strokeWidth: 2,
      textValue: text,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('schema 7 persists every advanced PDF annotation type', () async {
    final (db, store) = await setup();
    addTearDown(db.close);

    for (final type in PdfAnnotationObjectType.values) {
      await store.upsert(object(type, text: type.name));
    }

    final loaded = await store.listForDocument('doc-annotations');
    expect(LocalDatabase.schemaVersion, 7);
    expect(loaded, hasLength(PdfAnnotationObjectType.values.length));
    expect(
      loaded.map((value) => value.type).toSet(),
      PdfAnnotationObjectType.values.toSet(),
    );
  });

  test('upsert edits geometry, color and text without duplicating id', () async {
    final (db, store) = await setup();
    addTearDown(db.close);

    final original = object(PdfAnnotationObjectType.note, text: 'Original');
    await store.upsert(original);
    await store.upsert(
      original.copyWith(
        x: 0.4,
        y: 0.3,
        colorValue: 0xFFAA0000,
        textValue: 'Editada',
      ),
    );

    final loaded = await store.listForPage('doc-annotations', 2);
    expect(loaded, hasLength(1));
    expect(loaded.single.x, 0.4);
    expect(loaded.single.colorValue, 0xFFAA0000);
    expect(loaded.single.textValue, 'Editada');
  });

  test('deleting one object preserves the others', () async {
    final (db, store) = await setup();
    addTearDown(db.close);

    final first = object(PdfAnnotationObjectType.rectangle);
    final second = PdfAnnotationObject(
      id: 'other',
      documentId: first.documentId,
      pageNumber: first.pageNumber,
      type: PdfAnnotationObjectType.ellipse,
      x: 0.5,
      y: 0.5,
      width: 0.2,
      height: 0.2,
      colorValue: 0xFF000000,
      opacity: 1,
      strokeWidth: 2,
      createdAt: first.createdAt,
      updatedAt: first.updatedAt,
    );
    await store.upsert(first);
    await store.upsert(second);
    await store.delete(first.id);

    final loaded = await store.listForDocument('doc-annotations');
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'other');
  });

  test('rejects normalized bounds outside the page', () async {
    final (db, store) = await setup();
    addTearDown(db.close);
    final invalid = object(PdfAnnotationObjectType.rectangle).copyWith(
      x: 0.9,
      width: 0.3,
    );

    expect(() => store.upsert(invalid), throwsArgumentError);
  });
}
