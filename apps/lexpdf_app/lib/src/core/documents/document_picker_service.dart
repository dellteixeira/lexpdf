import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'document_provider.dart';
import 'local_document_identity.dart';
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
  static const LocalDocumentIdentity _identity = LocalDocumentIdentity();

  Future<DocumentRef?> pickPdf() async {
    if (Platform.isAndroid) {
      final picked = await _androidPicker.pickFile(
        extensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (picked == null) return null;

      return _identity.identifyLocal(
        path: picked.path,
        name: picked.name,
      );
    }

    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_pdfType],
    );
    if (file == null) return null;

    return _identity.identifyLocal(
      path: file.path,
      name: file.name,
    );
  }
}
