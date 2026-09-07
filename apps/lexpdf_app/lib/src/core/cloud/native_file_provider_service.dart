import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../documents/document_provider.dart';

class NativeFileProviderService {
  const NativeFileProviderService();

  Future<DocumentRef?> pickPdf({required Directory cacheDirectory}) async {
    const pdfTypes = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
    );
    final picked = await openFile(acceptedTypeGroups: const [pdfTypes]);
    if (picked == null) return null;
    await cacheDirectory.create(recursive: true);
    final id = 'file-provider-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final target = File(
      '${cacheDirectory.path}${Platform.pathSeparator}$id-$safeName',
    );
    await target.writeAsBytes(await picked.readAsBytes(), flush: true);
    return DocumentRef(
      id: id,
      name: picked.name,
      provider: DocumentProviderKind.iCloud,
      localPath: target.path,
      remotePath: picked.path,
      availableOffline: true,
      syncState: DocumentSyncState.synced,
    );
  }
}
