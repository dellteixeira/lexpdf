import 'local_database.dart';

/// Small persistent preference store for presentation-only workspace state.
///
/// This deliberately lives beside the encrypted local database instead of
/// introducing a second preference backend. The table is additive and does
/// not participate in document/annotation transactions.
class LocalWorkspaceUiPreferences {
  LocalWorkspaceUiPreferences(this.db);

  final LocalDatabase db;

  static const String panelVisibleKey = 'workspace.panel.visible';
  static const String statusBarVisibleKey = 'workspace.status_bar.visible';
  static const String denseToolbarKey = 'workspace.toolbar.dense';

  void ensureSchema() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS workspace_ui_preferences (
        preference_key TEXT PRIMARY KEY,
        preference_value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  bool readBool(String key, {required bool fallback}) {
    ensureSchema();
    final rows = db.database.select(
      'SELECT preference_value FROM workspace_ui_preferences WHERE preference_key = ? LIMIT 1;',
      [key],
    );
    if (rows.isEmpty) return fallback;
    final value = rows.single['preference_value'] as String?;
    if (value == '1' || value == 'true') return true;
    if (value == '0' || value == 'false') return false;
    return fallback;
  }

  void writeBool(String key, bool value) {
    ensureSchema();
    db.database.execute(
      '''
      INSERT INTO workspace_ui_preferences (
        preference_key,
        preference_value,
        updated_at
      ) VALUES (?, ?, ?)
      ON CONFLICT(preference_key) DO UPDATE SET
        preference_value = excluded.preference_value,
        updated_at = excluded.updated_at;
      ''',
      [key, value ? '1' : '0', DateTime.now().millisecondsSinceEpoch],
    );
  }
}
