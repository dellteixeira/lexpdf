import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'document_provider.dart';
import 'native_android_file_picker_service.dart';

class DocumentPickerService {
  const DocumentPickerService();

  static const _pdfType = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
  );

  static const NativeAndroidFilePickerService _androidPicker =
      NativeAndroidFilePickerService();

  Future<DocumentRef?> pickPdf() async {
    if (Platform.isAndroid) {
      final picked = await _androidPicker.pickFile(
        extensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (picked == null) return null;

      return DocumentRef(
        id: picked.path,
        name: picked.name,
        provider: DocumentProviderKind.local,
        localPath: picked.path,
        availableOffline: true,
        syncState: DocumentSyncState.localOnly,
      );
    }

    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_pdfType],
    );
    if (file == null) return null;

    return DocumentRef(
      id: file.path,
      name: file.name,
      provider: DocumentProviderKind.local,
      localPath: file.path,
      availableOffline: true,
      syncState: DocumentSyncState.localOnly,
    );
  }
}
