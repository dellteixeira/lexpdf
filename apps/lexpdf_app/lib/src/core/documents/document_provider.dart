enum DocumentProviderKind {
  local,
  googleDrive,
  oneDrive,
  iCloud,
  r2,
}

enum DocumentSyncState {
  localOnly,
  remoteOnly,
  synced,
  syncPending,
  downloading,
  uploading,
  conflict,
  error,
}

class DocumentRef {
  const DocumentRef({
    required this.id,
    required this.name,
    required this.provider,
    this.localPath,
    this.remoteId,
    this.remotePath,
    this.availableOffline = false,
    this.favorite = false,
    this.syncState = DocumentSyncState.localOnly,
  });

  final String id;
  final String name;
  final DocumentProviderKind provider;
  final String? localPath;
  final String? remoteId;
  final String? remotePath;
  final bool availableOffline;
  final bool favorite;
  final DocumentSyncState syncState;
}

abstract interface class DocumentProvider {
  DocumentProviderKind get kind;

  Future<List<DocumentRef>> list({String? parentId});

  Future<DocumentRef?> getById(String id);

  Future<String> ensureLocalCopy(DocumentRef document);

  Future<DocumentRef> upload(String localPath, {String? parentId});

  Future<void> rename(DocumentRef document, String newName);

  Future<void> move(DocumentRef document, {String? parentId});

  Future<void> delete(DocumentRef document);
}
