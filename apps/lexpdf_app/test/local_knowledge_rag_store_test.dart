import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_knowledge_rag_store.dart';

void main() {
  test('knowledge RAG collects annotations notebooks and visual descriptions', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final catalog = LocalDocumentCatalog(db);
    final store = LocalKnowledgeRagStore(db);
    await catalog.upsert(const DocumentRef(
      id: 'doc-1',
      name: 'Constitucional.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/a.pdf',
      availableOffline: true,
    ));
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('''
      INSERT INTO annotations(
        id, document_id, page_number, start_index, end_index, type,
        selected_text, color_value, opacity, created_at, updated_at
      ) VALUES ('a1', 'doc-1', 12, 0, 20, 'highlight',
                'contraditório e ampla defesa', 1, 1, ?, ?);
    ''', [now, now]);
    db.database.execute(
      "INSERT INTO notebooks(id, title, created_at, updated_at) VALUES ('n1', 'Constitucional', ?, ?);",
      [now, now],
    );
    db.database.execute('''
      INSERT INTO notebook_pages(
        id, notebook_id, page_number, width, height, background, created_at, updated_at
      ) VALUES ('p1', 'n1', 1, 1080, 1440, 'blank', ?, ?);
    ''', [now, now]);
    db.database.execute('''
      INSERT INTO notebook_page_documents(
        page_id, document_json, migrated_legacy_text, created_at, updated_at
      ) VALUES ('p1', ?, 0, ?, ?);
    ''', [jsonEncode({'nodes': [{'text': 'Minha nota de controle concentrado.'}]}), now, now]);
    await store.upsertVisualDescription(
      id: 'visual-1',
      sourceKind: 'pdf_visual',
      ownerId: 'doc-1',
      ownerTitle: 'Visual — Constitucional.pdf',
      pageNumber: 15,
      pdfDocumentId: 'doc-1',
      description: 'Diagrama relacionando controle difuso e concentrado.',
    );
    final pending = await store.sourcesNeedingIndex(model: 'test');
    expect(pending.any((item) => item.sourceKind == 'pdf_annotation'), isTrue);
    expect(pending.any((item) => item.sourceKind == 'notebook'), isTrue);
    expect(pending.any((item) => item.sourceKind == 'pdf_visual'), isTrue);
  });
}
