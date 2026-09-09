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
    String? localPath,
    this.remoteId,
    this.remotePath,
    this.checksum,
    this.remoteVersion,
    this.localVersion = 1,
    this.availableOffline = false,
    this.favorite = false,
    this.syncState = DocumentSyncState.localOnly,
  }) : localPath = localPath ??
            (provider == DocumentProviderKind.local ? id : null);

  final String id;
  final String name;
  final DocumentProviderKind provider;
  final String? localPath;
  final String? remoteId;
  final String? remotePath;
  final String? checksum;
  final String? remoteVersion;
  final int localVersion;
  final bool availableOffline;
  final bool favorite;
  final DocumentSyncState syncState;

  bool get hasLocalPath => localPath != null && localPath!.trim().isNotEmpty;

  DocumentRef copyWith({
    String? name,
    String? localPath,
    String? remoteId,
    String? remotePath,
    String? checksum,
    String? remoteVersion,
    int? localVersion,
    bool? availableOffline,
    bool? favorite,
    DocumentSyncState? syncState,
  }) => DocumentRef(
        id: id,
        name: name ?? this.name,
        provider: provider,
        localPath: localPath ?? this.localPath,
        remoteId: remoteId ?? this.remoteId,
        remotePath: remotePath ?? this.remotePath,
        checksum: checksum ?? this.checksum,
        remoteVersion: remoteVersion ?? this.remoteVersion,
        localVersion: localVersion ?? this.localVersion,
        availableOffline: availableOffline ?? this.availableOffline,
        favorite: favorite ?? this.favorite,
        syncState: syncState ?? this.syncState,
      );
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

abstract interface class SyncDocumentProvider implements DocumentProvider {
  Future<DocumentRef> replaceContent(DocumentRef document, String localPath);
}
