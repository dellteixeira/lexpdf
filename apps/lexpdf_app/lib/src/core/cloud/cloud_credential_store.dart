import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudCredentialStore {
  const CloudCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String provider, String accountId) =>
      'lexpdf.cloud.$provider.$accountId.token';

  Future<void> writeToken({
    required String provider,
    required String accountId,
    required String token,
  }) async {
    if (token.trim().isEmpty) throw ArgumentError('Token cannot be empty.');
    await _storage.write(key: _key(provider, accountId), value: token);
  }

  Future<String?> readToken({
    required String provider,
    required String accountId,
  }) => _storage.read(key: _key(provider, accountId));

  Future<void> deleteToken({
    required String provider,
    required String accountId,
  }) => _storage.delete(key: _key(provider, accountId));
}
