import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../documents/document_provider.dart';
import '../documents/native_android_file_picker_service.dart';

class NativeFileProviderService {
  const NativeFileProviderService();

  static const NativeAndroidFilePickerService _androidPicker =
      NativeAndroidFilePickerService();

  Future<DocumentRef?> pickPdf({required Directory cacheDirectory}) async {
    String sourcePath;
    String sourceName;

    if (Platform.isAndroid) {
      final picked = await _androidPicker.pickFile(
        extensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (picked == null) return null;
      sourcePath = picked.path;
      sourceName = picked.name;
    } else {
      const pdfTypes = XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      );
      final picked = await openFile(acceptedTypeGroups: const [pdfTypes]);
      if (picked == null) return null;
      sourcePath = picked.path;
      sourceName = picked.name;
    }

    await cacheDirectory.create(recursive: true);
    final id =
        'system-file-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final safeName =
        sourceName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final target = File(
      '${cacheDirectory.path}${Platform.pathSeparator}$id-$safeName',
    );

    // Never duplicate a potentially large PDF into Dart heap. Copy file-to-file
    // through the OS instead of readAsBytes/writeAsBytes.
    await File(sourcePath).copy(target.path);

    return DocumentRef(
      id: id,
      name: sourceName,
      provider: DocumentProviderKind.systemFile,
      localPath: target.path,
      remotePath: sourcePath,
      availableOffline: true,
      syncState: DocumentSyncState.synced,
    );
  }
}
