import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/cloud/cloud_oauth_service.dart';
import 'package:lexxpdf_app/src/core/cloud/direct_cloud_document_provider.dart';

void main() {
  test('OAuth configuration exposes provider readiness', () {
    final configured = CloudOAuthService(
      config: const CloudOAuthConfig(
        googleClientId: 'google-client',
        microsoftClientId: 'microsoft-client',
      ),
    );
    expect(configured.googleConfigured, isTrue);
    expect(configured.microsoftConfigured, isTrue);

    final empty = CloudOAuthService(
      config: const CloudOAuthConfig(
        googleClientId: '',
        microsoftClientId: '',
      ),
    );
    expect(empty.googleConfigured, isFalse);
    expect(empty.microsoftConfigured, isFalse);
  });

  test('cloud path helpers encode remote IDs safely', () {
    expect(
      DirectCloudDocumentProvider.safePathSegment('folder/file id'),
      'folder%2Ffile%20id',
    );
    expect(
      DirectCloudDocumentProvider.basename(r'C:\Users\lex\doc.pdf'),
      'doc.pdf',
    );
  });
}
