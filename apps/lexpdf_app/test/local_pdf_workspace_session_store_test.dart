import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_workspace_session_store.dart';

void main() {
  test('persists tab order active document and resume pages', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalPdfWorkspaceSessionStore(db);

    final a = DocumentRef(
      id: 'a',
      name: 'A.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/A.pdf',
      availableOffline: true,
    );
    final b = DocumentRef(
      id: 'b',
      name: 'B.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/B.pdf',
      availableOffline: true,
    );

    await store.save(
      tabs: [
        PdfWorkspaceTabState(document: a, initialPage: 12),
        PdfWorkspaceTabState(document: b, initialPage: 77),
      ],
      activeDocumentId: 'b',
    );

    final loaded = await store.load();
    expect(loaded.tabs.map((e) => e.document.id), <String>['a', 'b']);
    expect(loaded.tabs.map((e) => e.initialPage), <int>[12, 77]);
    expect(loaded.activeDocumentId, 'b');
    expect(loaded.updatedAt, isNotNull);
  });

  test('saving again atomically replaces the old tab session', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalPdfWorkspaceSessionStore(db);
    final a = DocumentRef(
      id: 'a',
      name: 'A.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/A.pdf',
    );
    final b = DocumentRef(
      id: 'b',
      name: 'B.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/B.pdf',
    );

    await store.save(
      tabs: [PdfWorkspaceTabState(document: a, initialPage: 2)],
      activeDocumentId: 'a',
    );
    await store.save(
      tabs: [PdfWorkspaceTabState(document: b, initialPage: 8)],
      activeDocumentId: 'b',
    );

    final loaded = await store.load();
    expect(loaded.tabs, hasLength(1));
    expect(loaded.tabs.single.document.id, 'b');
    expect(loaded.tabs.single.initialPage, 8);
  });

  test('clear removes the restorable workspace session', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalPdfWorkspaceSessionStore(db);
    final doc = DocumentRef(
      id: 'doc',
      name: 'Doc.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/Doc.pdf',
    );

    await store.save(
      tabs: [PdfWorkspaceTabState(document: doc, initialPage: 1)],
      activeDocumentId: 'doc',
    );
    await store.clear();

    final loaded = await store.load();
    expect(loaded.tabs, isEmpty);
    expect(loaded.activeDocumentId, isNull);
  });
}
