import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';

void main() {
  test('local documents recover localPath from legacy id values', () {
    const document = DocumentRef(
      id: r'C:\Users\Dell\Documents\material.pdf',
      name: 'material.pdf',
      provider: DocumentProviderKind.local,
      localPath: null,
      availableOffline: true,
    );

    expect(document.localPath, document.id);
    expect(document.hasLocalPath, isTrue);
  });

  test('remote documents do not reinterpret remote ids as local paths', () {
    const document = DocumentRef(
      id: 'remote-document-id',
      name: 'material.pdf',
      provider: DocumentProviderKind.googleDrive,
      localPath: null,
    );

    expect(document.localPath, isNull);
    expect(document.hasLocalPath, isFalse);
  });
}
