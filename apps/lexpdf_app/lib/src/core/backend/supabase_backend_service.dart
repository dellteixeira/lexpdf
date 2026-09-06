import 'package:supabase_flutter/supabase_flutter.dart';

import '../documents/document_provider.dart';
import '../storage/local_backend_map_store.dart';

class SupabaseBackendService {
  const SupabaseBackendService({
    required this.client,
    required this.mapStore,
  });

  final SupabaseClient client;
  final LocalBackendMapStore mapStore;

  User? get currentUser => client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) => client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => client.auth.signUp(email: email, password: password);

  Future<void> signOut() => client.auth.signOut();

  Future<String> ensureRemoteDocument(DocumentRef document) async {
    final user = _requireUser();
    final mapped = await mapStore.remoteId('document', document.id);
    if (mapped != null) return mapped;

    final row = await client
        .from('documents')
        .insert({
          'user_id': user.id,
          'title': document.name,
          'filename': document.name,
          'mime_type': 'application/pdf',
          'provider': _providerName(document.provider),
          'provider_file_id': document.remoteId,
          'remote_path': document.remotePath,
          'is_available_offline': document.availableOffline,
          'sync_status': _syncStateName(document.syncState),
        })
        .select('id, remote_version')
        .single();
    final remoteId = row['id'].toString();
    await mapStore.upsert(
      entityType: 'document',
      localId: document.id,
      remoteId: remoteId,
      remoteVersion: row['remote_version']?.toString(),
    );
    return remoteId;
  }

  Future<void> updateDocumentMetadata(
    DocumentRef document, {
    String? checksum,
    String? remoteVersion,
  }) async {
    final remoteId = await ensureRemoteDocument(document);
    await client.from('documents').update({
      'title': document.name,
      'filename': document.name,
      'provider': _providerName(document.provider),
      'provider_file_id': document.remoteId,
      'remote_path': document.remotePath,
      'checksum': checksum,
      'remote_version': remoteVersion,
      'is_available_offline': document.availableOffline,
      'sync_status': _syncStateName(document.syncState),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', remoteId);
  }

  Future<void> registerCloudAccount({
    required String provider,
    required String accountId,
    String? displayName,
    String? encryptedTokenRef,
  }) async {
    final user = _requireUser();
    await client.from('cloud_accounts').upsert({
      'user_id': user.id,
      'provider': provider,
      'provider_account_id': accountId,
      'display_name': displayName,
      'encrypted_token_ref': encryptedTokenRef,
      'status': 'connected',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,provider,provider_account_id');
  }

  Future<void> recordBackup({
    required String provider,
    required String backupType,
    required String status,
    String? location,
    String? checksum,
    int? sizeBytes,
  }) async {
    final user = _requireUser();
    await client.from('backup_history').insert({
      'user_id': user.id,
      'provider': provider,
      'backup_type': backupType,
      'location': location,
      'checksum': checksum,
      'size_bytes': sizeBytes,
      'status': status,
      if (status == 'validated')
        'validated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> recordConflict({
    String? localDocumentId,
    required String provider,
    String? localVersion,
    String? remoteVersion,
    String? localChecksum,
    String? remoteChecksum,
  }) async {
    final user = _requireUser();
    String? remoteDocumentId;
    if (localDocumentId != null) {
      remoteDocumentId = await mapStore.remoteId('document', localDocumentId);
    }
    await client.from('sync_conflicts').insert({
      'user_id': user.id,
      'document_id': remoteDocumentId,
      'local_version': localVersion,
      'remote_version': remoteVersion,
      'local_checksum': localChecksum,
      'remote_checksum': remoteChecksum,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  User _requireUser() {
    final user = currentUser;
    if (user == null) throw StateError('Supabase authentication is required.');
    return user;
  }

  static String _providerName(DocumentProviderKind kind) => switch (kind) {
        DocumentProviderKind.local => 'local',
        DocumentProviderKind.googleDrive => 'google_drive',
        DocumentProviderKind.oneDrive => 'onedrive',
        DocumentProviderKind.iCloud => 'icloud',
        DocumentProviderKind.r2 => 'r2',
      };

  static String _syncStateName(DocumentSyncState state) => switch (state) {
        DocumentSyncState.localOnly => 'local_only',
        DocumentSyncState.remoteOnly => 'remote_only',
        DocumentSyncState.synced => 'synced',
        DocumentSyncState.syncPending => 'sync_pending',
        DocumentSyncState.downloading => 'downloading',
        DocumentSyncState.uploading => 'uploading',
        DocumentSyncState.conflict => 'conflict',
        DocumentSyncState.error => 'error',
      };
}
