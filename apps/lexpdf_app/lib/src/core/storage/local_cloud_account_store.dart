import 'local_database.dart';

class LocalCloudAccount {
  const LocalCloudAccount({
    required this.provider,
    required this.accountId,
    required this.displayName,
    required this.gatewayUrl,
    required this.status,
    required this.updatedAt,
  });

  final String provider;
  final String accountId;
  final String displayName;
  final String gatewayUrl;
  final String status;
  final DateTime updatedAt;
}

class LocalCloudAccountStore {
  LocalCloudAccountStore(this.db) {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_cloud_accounts (
        provider TEXT NOT NULL,
        account_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        gateway_url TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'connected',
        updated_at TEXT NOT NULL,
        PRIMARY KEY(provider, account_id)
      );
    ''');
  }

  final LocalDatabase db;

  Future<void> upsert(LocalCloudAccount account) async {
    db.database.execute('''
      INSERT INTO local_cloud_accounts(
        provider, account_id, display_name, gateway_url, status, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(provider, account_id) DO UPDATE SET
        display_name = excluded.display_name,
        gateway_url = excluded.gateway_url,
        status = excluded.status,
        updated_at = excluded.updated_at;
    ''', [
      account.provider,
      account.accountId,
      account.displayName,
      account.gatewayUrl,
      account.status,
      account.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<LocalCloudAccount?> get(String provider, String accountId) async {
    final rows = db.database.select(
      '''
      SELECT * FROM local_cloud_accounts
      WHERE provider = ? AND account_id = ?
      LIMIT 1;
      ''',
      [provider, accountId],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<List<LocalCloudAccount>> list() async {
    final rows = db.database.select('''
      SELECT * FROM local_cloud_accounts ORDER BY provider, lower(display_name);
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> remove(String provider, String accountId) async {
    db.database.execute(
      'DELETE FROM local_cloud_accounts WHERE provider = ? AND account_id = ?;',
      [provider, accountId],
    );
  }

  LocalCloudAccount _fromRow(dynamic row) => LocalCloudAccount(
        provider: row['provider'] as String,
        accountId: row['account_id'] as String,
        displayName: row['display_name'] as String,
        gatewayUrl: row['gateway_url'] as String,
        status: row['status'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
