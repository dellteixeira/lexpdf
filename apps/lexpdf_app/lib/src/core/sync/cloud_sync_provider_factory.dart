import 'dart:io';

import '../cloud/cloud_gateway_document_provider.dart';
import '../cloud/direct_cloud_document_provider.dart';
import '../documents/document_provider.dart';
import '../storage/local_cloud_account_store.dart';

class CloudSyncProviderFactory {
  const CloudSyncProviderFactory({
    required this.accounts,
    required this.cacheRoot,
  });

  final LocalCloudAccountStore accounts;
  final Directory cacheRoot;

  Future<SyncDocumentProvider> resolve(
    String provider,
    String accountId,
  ) async {
    final account = await accounts.get(provider, accountId);
    if (account == null) {
      throw StateError('Cloud account $provider/$accountId is not configured.');
    }
    final cache = Directory(
      '${cacheRoot.path}${Platform.pathSeparator}$provider${Platform.pathSeparator}$accountId',
    );
    switch (provider) {
      case 'google_drive':
        return GoogleDriveDocumentProvider(
          accountId: accountId,
          cacheDirectory: cache,
        );
      case 'onedrive':
        return OneDriveDocumentProvider(
          accountId: accountId,
          cacheDirectory: cache,
        );
      case 'r2':
        final uri = Uri.tryParse(account.gatewayUrl);
        if (uri == null || !uri.hasScheme) {
          throw StateError('R2 gateway is not configured for $accountId.');
        }
        return CloudGatewayDocumentProvider(
          kind: DocumentProviderKind.r2,
          accountId: accountId,
          gatewayBaseUrl: uri,
          cacheDirectory: cache,
        );
      default:
        throw StateError('Provider $provider does not support managed sync.');
    }
  }
}
