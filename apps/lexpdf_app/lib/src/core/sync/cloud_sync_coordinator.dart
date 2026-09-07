import 'dart:io';

import '../documents/document_provider.dart';
import '../storage/local_document_catalog.dart';
import '../storage/local_sync_store.dart';
import 'sync_engine.dart';

typedef SyncProviderResolver = Future<SyncDocumentProvider> Function(
  String provider,
  String accountId,
);

enum SyncDecision { none, upload, download, conflict }

class SyncInspection {
  const SyncInspection({
    required this.decision,
    required this.localChecksum,
    required this.remote,
    this.checkpoint,
  });

  final SyncDecision decision;
  final String? localChecksum;
  final DocumentRef? remote;
  final LocalSyncCheckpoint? checkpoint;
}

class _CachedChecksum {
  const _CachedChecksum({
    required this.size,
    required this.modifiedMicros,
    required this.checksum,
  });

  final int size;
  final int modifiedMicros;
  final String checksum;
}

class CloudSyncCoordinator {
  CloudSyncCoordinator({
    required this.catalog,
    required this.store,
    required this.resolveProvider,
  });

  final LocalDocumentCatalog catalog;
  final LocalSyncStore store;
  final SyncProviderResolver resolveProvider;
  final Map<String, _CachedChecksum> _checksumCache = {};

  Future<SyncInspection> inspect({
    required DocumentRef document,
    required String provider,
    required String accountId,
  }) async {
    final cloud = await resolveProvider(provider, accountId);
    final localPath = document.localPath;
    final localExists = localPath != null && await File(localPath).exists();
    final localChecksum = localExists ? await _checksumForFile(localPath) : null;
    final remoteId = document.remoteId;
    final remote = remoteId == null ? null : await cloud.getById(remoteId);
    final checkpoint = await store.checkpoint(document.id, provider);

    if (checkpoint == null) {
      if (localExists && remote != null && document.syncState == DocumentSyncState.synced) {
        await _checkpoint(
          document: document,
          provider: provider,
          localChecksum: localChecksum,
          remote: remote,
        );
        return SyncInspection(
          decision: SyncDecision.none,
          localChecksum: localChecksum,
          remote: remote,
        );
      }
      if (localExists && remote == null) {
        return SyncInspection(
          decision: SyncDecision.upload,
          localChecksum: localChecksum,
          remote: null,
        );
      }
      if (!localExists && remote != null) {
        return SyncInspection(
          decision: SyncDecision.download,
          localChecksum: null,
          remote: remote,
        );
      }
      if (localExists && remote != null) {
        return SyncInspection(
          decision: SyncDecision.conflict,
          localChecksum: localChecksum,
          remote: remote,
        );
      }
      return SyncInspection(
        decision: SyncDecision.none,
        localChecksum: localChecksum,
        remote: remote,
      );
    }

    final localChanged = document.localVersion != checkpoint.localVersion ||
        localChecksum != checkpoint.localChecksum;
    final remoteDeleted = remote == null && checkpoint.remoteVersion != null;
    final remoteChanged = remoteDeleted ||
        (remote != null &&
            (remote.remoteVersion != checkpoint.remoteVersion ||
                (remote.checksum != null &&
                    checkpoint.remoteChecksum != null &&
                    remote.checksum != checkpoint.remoteChecksum)));

    final decision = switch ((localChanged, remoteChanged)) {
      (true, true) => SyncDecision.conflict,
      (true, false) => SyncDecision.upload,
      (false, true) => remoteDeleted ? SyncDecision.conflict : SyncDecision.download,
      (false, false) => SyncDecision.none,
    };
    return SyncInspection(
      decision: decision,
      localChecksum: localChecksum,
      remote: remote,
      checkpoint: checkpoint,
    );
  }

  Future<SyncDecision> scanAndQueue({
    required String documentId,
    required String provider,
    required String accountId,
  }) async {
    final document = await catalog.getById(documentId);
    if (document == null) throw StateError('Document $documentId not found.');
    final inspection = await inspect(
      document: document,
      provider: provider,
      accountId: accountId,
    );

    switch (inspection.decision) {
      case SyncDecision.none:
        await catalog.updateSyncMetadata(
          id: document.id,
          checksum: inspection.localChecksum,
          remoteVersion: inspection.remote?.remoteVersion,
          state: DocumentSyncState.synced,
        );
        break;
      case SyncDecision.upload:
        await store.enqueue(
          entityId: document.id,
          provider: provider,
          operation: LocalSyncOperation.upload,
          payload: {'accountId': accountId},
        );
        await catalog.updateSyncMetadata(
          id: document.id,
          state: DocumentSyncState.syncPending,
        );
        break;
      case SyncDecision.download:
        await store.enqueue(
          entityId: document.id,
          provider: provider,
          operation: LocalSyncOperation.download,
          payload: {'accountId': accountId},
        );
        await catalog.updateSyncMetadata(
          id: document.id,
          state: DocumentSyncState.syncPending,
        );
        break;
      case SyncDecision.conflict:
        await store.addConflict(
          entityId: document.id,
          provider: provider,
          localVersion: document.localVersion.toString(),
          remoteVersion: inspection.remote?.remoteVersion ?? 'deleted',
          localChecksum: inspection.localChecksum,
          remoteChecksum: inspection.remote?.checksum,
        );
        await catalog.updateSyncMetadata(
          id: document.id,
          state: DocumentSyncState.conflict,
        );
        break;
    }
    return inspection.decision;
  }

  Future<void> execute(LocalSyncItem item) async {
    final accountId = item.payload['accountId']?.toString();
    if (accountId == null || accountId.isEmpty) {
      throw StateError('Sync job ${item.id} has no accountId.');
    }
    final provider = await resolveProvider(item.provider, accountId);
    final document = await catalog.getById(item.entityId);
    if (document == null) {
      throw StateError('Document ${item.entityId} no longer exists.');
    }

    switch (item.operation) {
      case LocalSyncOperation.upload:
        await _upload(document, item.provider, provider);
        break;
      case LocalSyncOperation.download:
        await _download(document, item.provider, provider);
        break;
      case LocalSyncOperation.delete:
        await provider.delete(document);
        break;
      case LocalSyncOperation.metadata:
        final newName = item.payload['name']?.toString();
        if (newName != null && newName.isNotEmpty) {
          await provider.rename(document, newName);
        }
        break;
    }
  }

  SyncEngine engine() => SyncEngine(
        store: store,
        executors: {
          'google_drive': execute,
          'onedrive': execute,
          'r2': execute,
        },
      );

  Future<void> resolveConflict({
    required LocalSyncConflict conflict,
    required ConflictResolution resolution,
    required String accountId,
  }) async {
    final document = await catalog.getById(conflict.entityId);
    if (document == null) throw StateError('Conflict document no longer exists.');
    final provider = await resolveProvider(conflict.provider, accountId);

    switch (resolution) {
      case ConflictResolution.keepLocal:
        await _upload(document, conflict.provider, provider);
        break;
      case ConflictResolution.keepRemote:
        await _download(document, conflict.provider, provider);
        break;
      case ConflictResolution.keepBoth:
        final path = document.localPath;
        if (path != null && await File(path).exists()) {
          final copyPath = _conflictCopyPath(path);
          await File(path).copy(copyPath);
          final localCopy = DocumentRef(
            id: 'local-conflict-${DateTime.now().microsecondsSinceEpoch}',
            name: '${document.name} (cópia local)',
            provider: DocumentProviderKind.local,
            localPath: copyPath,
            availableOffline: true,
            syncState: DocumentSyncState.localOnly,
          );
          await catalog.upsert(localCopy);
        }
        await _download(document, conflict.provider, provider);
        break;
    }
    await store.resolveConflict(conflict.id, resolution);
  }

  Future<void> _upload(
    DocumentRef document,
    String providerName,
    SyncDocumentProvider provider,
  ) async {
    final path = document.localPath;
    if (path == null || !await File(path).exists()) {
      throw FileSystemException('Local sync source is missing.', path);
    }
    final localChecksum = await _checksumForFile(path);
    final remote = document.remoteId == null
        ? await provider.upload(path, parentId: document.remotePath)
        : await provider.replaceContent(document, path);
    final updated = DocumentRef(
      id: document.id,
      name: remote.name,
      provider: document.provider,
      localPath: path,
      remoteId: remote.remoteId ?? remote.id,
      remotePath: remote.remotePath,
      checksum: localChecksum,
      remoteVersion: remote.remoteVersion,
      localVersion: document.localVersion,
      availableOffline: true,
      favorite: document.favorite,
      syncState: DocumentSyncState.synced,
    );
    await catalog.upsert(updated);
    await _checkpoint(
      document: updated,
      provider: providerName,
      localChecksum: localChecksum,
      remote: remote,
    );
  }

  Future<void> _download(
    DocumentRef document,
    String providerName,
    SyncDocumentProvider provider,
  ) async {
    final remoteId = document.remoteId;
    if (remoteId == null) throw StateError('Document has no remoteId.');
    final remote = await provider.getById(remoteId);
    if (remote == null) throw StateError('Remote document was deleted.');
    final remoteOnly = DocumentRef(
      id: document.id,
      name: remote.name,
      provider: document.provider,
      remoteId: remote.remoteId ?? remote.id,
      remotePath: remote.remotePath,
      checksum: remote.checksum,
      remoteVersion: remote.remoteVersion,
      syncState: DocumentSyncState.remoteOnly,
    );
    final downloadedPath = await provider.ensureLocalCopy(remoteOnly);
    final targetPath = document.localPath;
    var finalPath = downloadedPath;
    String localChecksum;

    if (targetPath != null && !_samePath(targetPath, downloadedPath)) {
      localChecksum = await _replaceFileAtomically(
        sourcePath: downloadedPath,
        targetPath: targetPath,
        expectedChecksum: remote.checksum,
      );
      finalPath = targetPath;
    } else {
      localChecksum = await _checksumForFile(finalPath);
      _verifyExpectedChecksum(
        actual: localChecksum,
        expected: remote.checksum,
        path: finalPath,
      );
    }

    final updated = DocumentRef(
      id: document.id,
      name: remote.name,
      provider: document.provider,
      localPath: finalPath,
      remoteId: remote.remoteId ?? remote.id,
      remotePath: remote.remotePath,
      checksum: localChecksum,
      remoteVersion: remote.remoteVersion,
      localVersion: document.localVersion,
      availableOffline: true,
      favorite: document.favorite,
      syncState: DocumentSyncState.synced,
    );
    await catalog.upsert(updated);
    await _checkpoint(
      document: updated,
      provider: providerName,
      localChecksum: localChecksum,
      remote: remote,
    );
  }

  Future<String> _replaceFileAtomically({
    required String sourcePath,
    required String targetPath,
    String? expectedChecksum,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Downloaded sync file is missing.', sourcePath);
    }
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final partial = File('$targetPath.lexpdf-sync-partial-$token');
    final backup = File('$targetPath.lexpdf-sync-backup-$token');
    var parkedOriginal = false;

    try {
      await source.openRead().pipe(partial.openWrite());
      final checksum = await _checksumForFile(partial.path);
      _verifyExpectedChecksum(
        actual: checksum,
        expected: expectedChecksum,
        path: partial.path,
      );

      if (await target.exists()) {
        await target.rename(backup.path);
        parkedOriginal = true;
      }
      try {
        await partial.rename(target.path);
      } catch (_) {
        if (parkedOriginal && await backup.exists()) {
          await backup.rename(target.path);
          parkedOriginal = false;
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
      parkedOriginal = false;
      _checksumCache.remove(partial.path);
      await _rememberChecksum(target.path, checksum);
      return checksum;
    } finally {
      if (await partial.exists()) await partial.delete();
      _checksumCache.remove(partial.path);
      if (parkedOriginal && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      } else if (await backup.exists()) {
        await backup.delete();
      }
    }
  }

  Future<String> _checksumForFile(String path) async {
    final file = File(path);
    final stat = await file.stat();
    final modifiedMicros = stat.modified.toUtc().microsecondsSinceEpoch;
    final cached = _checksumCache[path];
    if (cached != null &&
        cached.size == stat.size &&
        cached.modifiedMicros == modifiedMicros) {
      return cached.checksum;
    }
    final checksum = await SyncEngine.sha256File(path);
    _checksumCache[path] = _CachedChecksum(
      size: stat.size,
      modifiedMicros: modifiedMicros,
      checksum: checksum,
    );
    return checksum;
  }

  Future<void> _rememberChecksum(String path, String checksum) async {
    final stat = await File(path).stat();
    _checksumCache[path] = _CachedChecksum(
      size: stat.size,
      modifiedMicros: stat.modified.toUtc().microsecondsSinceEpoch,
      checksum: checksum,
    );
  }

  void _verifyExpectedChecksum({
    required String actual,
    required String? expected,
    required String path,
  }) {
    if (expected != null && expected.isNotEmpty && actual != expected) {
      throw StateError('Downloaded file checksum mismatch: $path');
    }
  }

  Future<void> _checkpoint({
    required DocumentRef document,
    required String provider,
    required String? localChecksum,
    required DocumentRef remote,
  }) => store.saveCheckpoint(
        LocalSyncCheckpoint(
          entityId: document.id,
          provider: provider,
          localVersion: document.localVersion,
          localChecksum: localChecksum,
          remoteVersion: remote.remoteVersion,
          remoteChecksum: remote.checksum,
          syncedAt: DateTime.now().toUtc(),
        ),
      );

  static bool _samePath(String a, String b) {
    final left = File(a).absolute.path;
    final right = File(b).absolute.path;
    return Platform.isWindows
        ? left.toLowerCase() == right.toLowerCase()
        : left == right;
  }

  static String _conflictCopyPath(String path) {
    final dot = path.lastIndexOf('.');
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    if (dot <= 0) return '$path.local-$stamp';
    return '${path.substring(0, dot)}.local-$stamp${path.substring(dot)}';
  }
}
