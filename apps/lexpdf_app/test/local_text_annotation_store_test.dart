import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_text_annotation_store.dart';

void main() {
  test('persists, updates and deletes text annotations offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    final store = LocalTextAnnotationStore(database);

    const document = DocumentRef(
      id: 'doc-annotations',
      name: 'Anotacoes.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/Anotacoes.pdf',
      availableOffline: true,
    );
    await catalog.upsert(document);

    final now = DateTime.utc(2026, 9, 6, 12);
    final annotation = LocalTextAnnotation(
      id: 'annotation-1',
      documentId: document.id,
      pageNumber: 3,
      startIndex: 10,
      endIndex: 22,
      type: TextAnnotationType.highlight,
      selectedText: 'texto marcado',
      colorValue: 0xFFFFD54F,
      opacity: 0.35,
      createdAt: now,
      updatedAt: now,
    );

    await store.upsert(annotation);
    var annotations = await store.listForDocument(document.id);
    expect(annotations, hasLength(1));
    expect(annotations.single.pageNumber, 3);
    expect(annotations.single.type, TextAnnotationType.highlight);
    expect(annotations.single.selectedText, 'texto marcado');
    expect(annotations.single.opacity, 0.35);

    await store.upsert(
      annotation.copyWith(
        type: TextAnnotationType.underline,
        colorValue: 0xFF1976D2,
        opacity: 1,
      ),
    );
    annotations = await store.listForPage(document.id, 3);
    expect(annotations, hasLength(1));
    expect(annotations.single.type, TextAnnotationType.underline);
    expect(annotations.single.colorValue, 0xFF1976D2);

    await store.delete(annotation.id);
    expect(await store.listForDocument(document.id), isEmpty);
  });

  test('rejects invalid text annotation geometry', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalTextAnnotationStore(database);
    final now = DateTime.utc(2026, 9, 6);

    final invalid = LocalTextAnnotation(
      id: 'invalid',
      documentId: 'missing',
      pageNumber: 0,
      startIndex: 5,
      endIndex: 2,
      type: TextAnnotationType.strikeout,
      colorValue: 0xFFD32F2F,
      opacity: 1,
      createdAt: now,
      updatedAt: now,
    );

    expect(() => store.upsert(invalid), throwsArgumentError);
  });
}
