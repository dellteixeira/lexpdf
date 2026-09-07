import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_sync_store.dart';
import 'package:lexpdf_app/src/core/sync/cloud_sync_coordinator.dart';
import 'package:lexpdf_app/src/core/sync/sync_engine.dart';

void main() {
  late Directory temp;
  late LocalDatabase db;
  late LocalDocumentCatalog catalog;
  late LocalSyncStore store;
  late _FakeSyncProvider provider;
  late CloudSyncCoordinator coordinator;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lexpdf-phase10-');
    db = LocalDatabase.inMemory();
    catalog = LocalDocumentCatalog(db);
    store = LocalSyncStore(db);
    provider = _FakeSyncProvider(Directory('${temp.path}/remote-cache'));
    coordinator = CloudSyncCoordinator(
      catalog: catalog,
      store: store,
      resolveProvider: (_, __) async => provider,
    );
  });

  tearDown(() async {
    db.close();
    await temp.delete(recursive: true);
  });

  test('local change queues in-place upload and saves new checkpoint', () async {
    final local = File('${temp.path}/doc.pdf');
    await local.writeAsString('baseline');
    provider.seed('remote-1', 'baseline');
    await _insertSynced(catalog, local.path);

    expect(
      (await coordinator.inspect(
        document: (await catalog.getById('doc-1'))!,
        provider: 'google_drive',
        accountId: 'personal',
      ))
          .decision,
      SyncDecision.none,
    );

    await local.writeAsString('local changed');
    await catalog.incrementLocalVersion('doc-1');
    expect(
      await coordinator.scanAndQueue(
        documentId: 'doc-1',
        provider: 'google_drive',
        accountId: 'personal',
      ),
      SyncDecision.upload,
    );

    expect(await coordinator.engine().drain(), 1);
    expect(provider.text('remote-1'), 'local changed');
    final current = (await catalog.getById('doc-1'))!;
    expect(current.remoteId, 'remote-1');
    expect(current.syncState, DocumentSyncState.synced);
    final checkpoint = await store.checkpoint('doc-1', 'google_drive');
    expect(checkpoint, isNotNull);
    expect(checkpoint!.localChecksum, await SyncEngine.sha256File(local.path));
  });

  test('remote change queues download and updates local file', () async {
    final local = File('${temp.path}/doc.pdf');
    await local.writeAsString('baseline');
    provider.seed('remote-1', 'baseline');
    await _insertSynced(catalog, local.path);
    await coordinator.inspect(
      document: (await catalog.getById('doc-1'))!,
      provider: 'google_drive',
      accountId: 'personal',
    );

    provider.replaceRemote('remote-1', 'remote changed');
    expect(
      await coordinator.scanAndQueue(
        documentId: 'doc-1',
        provider: 'google_drive',
        accountId: 'personal',
      ),
      SyncDecision.download,
    );
    expect(await coordinator.engine().drain(), 1);
    expect(await local.readAsString(), 'remote changed');
  });

  test('simultaneous local and remote changes create conflict and keepBoth preserves both', () async {
    final local = File('${temp.path}/doc.pdf');
    await local.writeAsString('baseline');
    provider.seed('remote-1', 'baseline');
    await _insertSynced(catalog, local.path);
    await coordinator.inspect(
      document: (await catalog.getById('doc-1'))!,
      provider: 'google_drive',
      accountId: 'personal',
    );

    await local.writeAsString('local changed');
    await catalog.incrementLocalVersion('doc-1');
    provider.replaceRemote('remote-1', 'remote changed');
    expect(
      await coordinator.scanAndQueue(
        documentId: 'doc-1',
        provider: 'google_drive',
        accountId: 'personal',
      ),
      SyncDecision.conflict,
    );
    final conflict = (await store.listConflicts(unresolvedOnly: true)).single;
    await coordinator.resolveConflict(
      conflict: conflict,
      resolution: ConflictResolution.keepBoth,
      accountId: 'personal',
    );

    expect(await local.readAsString(), 'remote changed');
    final localCopies = (await catalog.list(limit: 20))
        .where((document) => document.provider == DocumentProviderKind.local)
        .toList();
    expect(localCopies, hasLength(1));
    expect(await File(localCopies.single.localPath!).readAsString(), 'local changed');
    expect(await store.listConflicts(unresolvedOnly: true), isEmpty);
  });

  test('queue deduplicates active work and recovers interrupted running job', () async {
    final first = await store.enqueue(
      entityId: 'doc-1',
      provider: 'google_drive',
      operation: LocalSyncOperation.upload,
      payload: const {'accountId': 'personal'},
    );
    final duplicate = await store.enqueue(
      entityId: 'doc-1',
      provider: 'google_drive',
      operation: LocalSyncOperation.upload,
      payload: const {'accountId': 'personal'},
    );
    expect(duplicate.id, first.id);

    await store.markRunning(first.id);
    expect((await store.get(first.id))!.status, LocalSyncStatus.running);
    await store.recoverInterrupted();
    expect((await store.get(first.id))!.status, LocalSyncStatus.pending);
  });

  test('document-account binding is persistent and deterministic', () async {
    await store.bindAccount(
      entityId: 'doc-1',
      provider: 'google_drive',
      accountId: 'work',
    );
    final binding = await store.bindingFor('doc-1');
    expect(binding, isNotNull);
    expect(binding!.provider, 'google_drive');
    expect(binding.accountId, 'work');
  });
}

Future<void> _insertSynced(LocalDocumentCatalog catalog, String path) async {
  await catalog.upsert(
    DocumentRef(
      id: 'doc-1',
      name: 'doc.pdf',
      provider: DocumentProviderKind.googleDrive,
      localPath: path,
      remoteId: 'remote-1',
      availableOffline: true,
      syncState: DocumentSyncState.synced,
    ),
  );
}

class _FakeSyncProvider implements SyncDocumentProvider {
  _FakeSyncProvider(this.cacheDirectory);

  final Directory cacheDirectory;
  final Map<String, List<int>> _bytes = {};
  final Map<String, int> _revisions = {};

  @override
  DocumentProviderKind get kind => DocumentProviderKind.googleDrive;

  void seed(String id, String text) {
    _bytes[id] = text.codeUnits;
    _revisions[id] = 1;
  }

  void replaceRemote(String id, String text) {
    _bytes[id] = text.codeUnits;
    _revisions[id] = (_revisions[id] ?? 0) + 1;
  }

  String text(String id) => String.fromCharCodes(_bytes[id]!);

  DocumentRef _ref(String id, {String? localPath}) => DocumentRef(
        id: id,
        name: 'doc.pdf',
        provider: kind,
        localPath: localPath,
        remoteId: id,
        checksum: SyncEngine.sha256Bytes(_bytes[id]!),
        remoteVersion: 'r${_revisions[id]}',
        availableOffline: localPath != null,
        syncState: localPath == null
            ? DocumentSyncState.remoteOnly
            : DocumentSyncState.synced,
      );

  @override
  Future<List<DocumentRef>> list({String? parentId}) async =>
      _bytes.keys.map(_ref).toList(growable: false);

  @override
  Future<DocumentRef?> getById(String id) async =>
      _bytes.containsKey(id) ? _ref(id) : null;

  @override
  Future<String> ensureLocalCopy(DocumentRef document) async {
    final id = document.remoteId ?? document.id;
    await cacheDirectory.create(recursive: true);
    final file = File('${cacheDirectory.path}/$id.pdf');
    await file.writeAsBytes(_bytes[id]!, flush: true);
    return file.path;
  }

  @override
  Future<DocumentRef> upload(String localPath, {String? parentId}) async {
    final id = 'remote-${_bytes.length + 1}';
    _bytes[id] = await File(localPath).readAsBytes();
    _revisions[id] = 1;
    return _ref(id, localPath: localPath);
  }

  @override
  Future<DocumentRef> replaceContent(
    DocumentRef document,
    String localPath,
  ) async {
    final id = document.remoteId ?? document.id;
    _bytes[id] = await File(localPath).readAsBytes();
    _revisions[id] = (_revisions[id] ?? 0) + 1;
    return _ref(id, localPath: localPath);
  }

  @override
  Future<void> rename(DocumentRef document, String newName) async {}

  @override
  Future<void> move(DocumentRef document, {String? parentId}) async {}

  @override
  Future<void> delete(DocumentRef document) async {
    _bytes.remove(document.remoteId ?? document.id);
  }
}
