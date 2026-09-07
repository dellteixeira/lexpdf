import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_form_store.dart';

void main() {
  test('persists and replaces PDF form values offline', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final catalog = LocalDocumentCatalog(db);
    await catalog.upsert(
      const DocumentRef(
        id: 'form-doc',
        name: 'form.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/form.pdf',
        availableOffline: true,
      ),
    );

    final store = LocalPdfFormStore(db);
    await store.setValue(
      documentId: 'form-doc',
      fieldName: 'name',
      value: 'Maria',
    );
    await store.setValue(
      documentId: 'form-doc',
      fieldName: 'accepted',
      value: true,
    );

    var values = await store.load('form-doc');
    expect(values['name'], 'Maria');
    expect(values['accepted'], isTrue);

    await store.replaceAll(
      documentId: 'form-doc',
      values: {'name': 'João', 'choice': 'B'},
    );
    values = await store.load('form-doc');
    expect(values, {'name': 'João', 'choice': 'B'});

    await store.clear('form-doc');
    expect(await store.load('form-doc'), isEmpty);
  });
}
