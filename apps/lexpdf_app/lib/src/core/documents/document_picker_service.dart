import 'package:file_selector/file_selector.dart';

import 'document_provider.dart';

class DocumentPickerService {
  const DocumentPickerService();

  static const _pdfType = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
  );

  Future<DocumentRef?> pickPdf() async {
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
