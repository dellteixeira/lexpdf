import 'dart:convert';

import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/services/import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_notebook_document_store.dart';

void main() {
  test('schema v11 persists one rich document per notebook page', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);

    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute(
      'INSERT INTO notebooks(id, title, created_at, updated_at) VALUES (?, ?, ?, ?);',
      ['notebook-doc', 'Documento', now, now],
    );
    db.database.execute(
      '''
      INSERT INTO notebook_pages(
        id, notebook_id, page_number, width, height, background, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      ['page-doc', 'notebook-doc', 1, 1080.0, 1440.0, 'blank', now, now],
    );

    final document = FluentDocument();
    document.loadContent(
      ImportService().importFromHtml('<p><strong>LexPDF</strong> rico</p>'),
    );
    final sourceText = document.content.text;
    expect(sourceText, contains('LexPDF'));
    expect(sourceText, contains('rico'));

    final store = LocalNotebookDocumentStore(db);
    await store.upsert(
      pageId: 'page-doc',
      documentJson: document.toJson(),
      migratedLegacyText: true,
    );

    final record = await store.read('page-doc');
    expect(record, isNotNull);
    expect(record!.migratedLegacyText, isTrue);
    final restored = FluentDocument.fromJson(
      jsonDecode(record.documentJson) as Map<String, dynamic>,
    );
    addTearDown(restored.dispose);
    expect(restored.content.text, sourceText);
  });

  test(
    'rich document follows page copy without deleting legacy data',
    () async {
      final db = LocalDatabase.inMemory();
      addTearDown(db.close);
      final now = DateTime.now().toUtc().toIso8601String();
      db.database.execute(
        'INSERT INTO notebooks(id, title, created_at, updated_at) VALUES (?, ?, ?, ?);',
        ['notebook-copy', 'Copy', now, now],
      );
      for (final entry in [('source', 1), ('target', 2)]) {
        db.database.execute(
          '''
        INSERT INTO notebook_pages(
          id, notebook_id, page_number, width, height, background, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        ''',
          [
            entry.$1,
            'notebook-copy',
            entry.$2,
            1080.0,
            1440.0,
            'blank',
            now,
            now,
          ],
        );
      }

      final store = LocalNotebookDocumentStore(db);
      await store.upsert(
        pageId: 'source',
        documentJson: '{"nodes":{"type":"root","nodes":[]},"settings":{}}',
        migratedLegacyText: true,
      );
      await store.copyPageDocument('source', 'target');

      final copied = await store.read('target');
      expect(copied, isNotNull);
      expect(copied!.migratedLegacyText, isTrue);
    },
  );
}
