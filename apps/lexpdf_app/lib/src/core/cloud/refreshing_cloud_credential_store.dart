import 'cloud_credential_store.dart';
import 'cloud_oauth_service.dart';

class RefreshingCloudCredentialStore extends CloudCredentialStore {
  RefreshingCloudCredentialStore({
    CloudOAuthService? oauth,
  }) : _oauth = oauth ?? CloudOAuthService();

  final CloudOAuthService _oauth;

  @override
  Future<String?> readToken({
    required String provider,
    required String accountId,
  }) async {
    if (provider == 'google_drive' || provider == 'onedrive') {
      return _oauth.validAccessToken(provider: provider, accountId: accountId);
    }
    return super.readToken(provider: provider, accountId: accountId);
  }
}
