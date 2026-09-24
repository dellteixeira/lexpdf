import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'document_provider.dart';

class DocumentPickerService {
  const DocumentPickerService();

  static const _pdfType = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
  );

  static const MethodChannel _androidPicker =
      MethodChannel('lexpdf/native_pdf_picker');

  Future<DocumentRef?> pickPdf() async {
    if (Platform.isAndroid) {
      final result =
          await _androidPicker.invokeMapMethod<String, dynamic>('pickPdf');
      if (result == null) return null;

      final path = result['path'] as String?;
      final name = result['name'] as String?;
      if (path == null || path.trim().isEmpty) {
        throw const PlatformException(
          code: 'picker_missing_path',
          message: 'Android picker returned no local PDF path.',
        );
      }

      return DocumentRef(
        id: path,
        name: (name == null || name.trim().isEmpty)
            ? path.split(Platform.pathSeparator).last
            : name,
        provider: DocumentProviderKind.local,
        localPath: path,
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
