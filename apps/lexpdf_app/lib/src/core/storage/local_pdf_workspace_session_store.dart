import '../documents/document_provider.dart';
import 'local_database.dart';

class PdfWorkspaceTabState {
  const PdfWorkspaceTabState({
    required this.document,
    required this.initialPage,
  });

  final DocumentRef document;
  final int initialPage;
}

class PdfWorkspaceSessionState {
  const PdfWorkspaceSessionState({
    required this.tabs,
    required this.activeDocumentId,
    required this.updatedAt,
  });

  final List<PdfWorkspaceTabState> tabs;
  final String? activeDocumentId;
  final DateTime? updatedAt;
}

/// Persists the lightweight shell around the PDF editor.
///
/// The actual PDF annotations and ink remain in their dedicated stores. This
/// store only remembers which documents were open, their latest known resume
/// page and the active tab so an interrupted workspace can be reconstructed.
class LocalPdfWorkspaceSessionStore {
  LocalPdfWorkspaceSessionStore(this.db) {
    _ensureTables();
  }

  final LocalDatabase db;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS pdf_workspace_session (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        active_document_id TEXT,
        updated_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS pdf_workspace_tabs (
        position INTEGER PRIMARY KEY CHECK(position >= 0),
        document_id TEXT NOT NULL,
        name TEXT NOT NULL,
        provider TEXT NOT NULL,
        local_path TEXT NOT NULL,
        initial_page INTEGER NOT NULL DEFAULT 1 CHECK(initial_page >= 1)
      );
    ''');
  }

  Future<PdfWorkspaceSessionState> load() async {
    final sessionRows = db.database.select(
      'SELECT active_document_id, updated_at FROM pdf_workspace_session '
      'WHERE singleton_id = 1 LIMIT 1;',
    );
    final tabRows = db.database.select('''
      SELECT position, document_id, name, provider, local_path, initial_page
      FROM pdf_workspace_tabs
      ORDER BY position ASC;
    ''');

    final tabs = <PdfWorkspaceTabState>[];
    for (final row in tabRows) {
      final path = row['local_path'] as String;
      if (path.trim().isEmpty) continue;
      final providerName = row['provider'] as String;
      final provider = DocumentProviderKind.values.firstWhere(
        (value) => value.name == providerName,
        orElse: () => DocumentProviderKind.local,
      );
      tabs.add(
        PdfWorkspaceTabState(
          document: DocumentRef(
            id: row['document_id'] as String,
            name: row['name'] as String,
            provider: provider,
            localPath: path,
            availableOffline: true,
            syncState: DocumentSyncState.localOnly,
          ),
          initialPage: row['initial_page'] as int,
        ),
      );
    }

    if (sessionRows.isEmpty) {
      return PdfWorkspaceSessionState(
        tabs: tabs,
        activeDocumentId: null,
        updatedAt: null,
      );
    }
    final row = sessionRows.first;
    return PdfWorkspaceSessionState(
      tabs: tabs,
      activeDocumentId: row['active_document_id'] as String?,
      updatedAt: DateTime.tryParse(row['updated_at'] as String),
    );
  }

  Future<void> save({
    required List<PdfWorkspaceTabState> tabs,
    required String? activeDocumentId,
  }) async {
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute('DELETE FROM pdf_workspace_tabs;');
      for (var i = 0; i < tabs.length; i++) {
        final tab = tabs[i];
        final path = tab.document.localPath;
        if (path == null || path.trim().isEmpty) continue;
        db.database.execute('''
          INSERT INTO pdf_workspace_tabs(
            position, document_id, name, provider, local_path, initial_page
          ) VALUES (?, ?, ?, ?, ?, ?);
        ''', [
          i,
          tab.document.id,
          tab.document.name,
          tab.document.provider.name,
          path,
          tab.initialPage < 1 ? 1 : tab.initialPage,
        ]);
      }
      db.database.execute('''
        INSERT INTO pdf_workspace_session(
          singleton_id, active_document_id, updated_at
        ) VALUES (1, ?, ?)
        ON CONFLICT(singleton_id) DO UPDATE SET
          active_document_id = excluded.active_document_id,
          updated_at = excluded.updated_at;
      ''', [
        activeDocumentId,
        DateTime.now().toUtc().toIso8601String(),
      ]);
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> clear() async {
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute('DELETE FROM pdf_workspace_tabs;');
      db.database.execute('DELETE FROM pdf_workspace_session;');
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }
}
