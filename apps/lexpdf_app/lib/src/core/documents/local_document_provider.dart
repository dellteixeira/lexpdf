import 'dart:io';

import 'document_provider.dart';

class LocalDocumentProvider implements DocumentProvider {
  const LocalDocumentProvider();

  @override
  DocumentProviderKind get kind => DocumentProviderKind.local;

  @override
  Future<List<DocumentRef>> list({String? parentId}) async {
    if (parentId == null || parentId.isEmpty) {
      return const [];
    }

    final directory = Directory(parentId);
    if (!await directory.exists()) return const [];

    final documents = <DocumentRef>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.pdf')) continue;

      documents.add(
        DocumentRef(
          id: entity.path,
          name: _basename(entity.path),
          provider: DocumentProviderKind.local,
          localPath: entity.path,
          availableOffline: true,
          syncState: DocumentSyncState.localOnly,
        ),
      );
    }

    documents.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return documents;
  }

  @override
  Future<DocumentRef?> getById(String id) async {
    final file = File(id);
    if (!await file.exists()) return null;

    return DocumentRef(
      id: id,
      name: _basename(id),
      provider: DocumentProviderKind.local,
      localPath: id,
      availableOffline: true,
      syncState: DocumentSyncState.localOnly,
    );
  }

  @override
  Future<String> ensureLocalCopy(DocumentRef document) async {
    final path = document.localPath;
    if (path == null || !await File(path).exists()) {
      throw FileSystemException('Local document is unavailable', path);
    }
    return path;
  }

  @override
  Future<DocumentRef> upload(String localPath, {String? parentId}) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw FileSystemException('Source file does not exist', localPath);
    }

    if (parentId == null || parentId.isEmpty) {
      return (await getById(localPath))!;
    }

    final targetDirectory = Directory(parentId);
    await targetDirectory.create(recursive: true);
    final targetPath = '${targetDirectory.path}${Platform.pathSeparator}${_basename(localPath)}';
    final target = await source.copy(targetPath);
    return (await getById(target.path))!;
  }

  @override
  Future<void> rename(DocumentRef document, String newName) async {
    final path = await ensureLocalCopy(document);
    final file = File(path);
    final parent = file.parent.path;
    await file.rename('$parent${Platform.pathSeparator}$newName');
  }

  @override
  Future<void> move(DocumentRef document, {String? parentId}) async {
    if (parentId == null || parentId.isEmpty) return;
    final path = await ensureLocalCopy(document);
    final file = File(path);
    await Directory(parentId).create(recursive: true);
    await file.rename('$parentId${Platform.pathSeparator}${_basename(path)}');
  }

  @override
  Future<void> delete(DocumentRef document) async {
    final path = document.localPath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
