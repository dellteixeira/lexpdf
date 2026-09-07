import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudOAuthCredential {
  const CloudOAuthCredential({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().toUtc().isAfter(
          expiry.subtract(const Duration(minutes: 2)),
        );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
      };

  static CloudOAuthCredential fromJson(Map<String, dynamic> value) =>
      CloudOAuthCredential(
        accessToken: value['accessToken']?.toString() ?? '',
        refreshToken: value['refreshToken']?.toString(),
        expiresAt: value['expiresAt'] == null
            ? null
            : DateTime.tryParse(value['expiresAt'].toString())?.toUtc(),
      );
}

class CloudCredentialStore {
  const CloudCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String provider, String accountId) =>
      'lexpdf.cloud.$provider.$accountId.token';
  String _oauthKey(String provider, String accountId) =>
      'lexpdf.cloud.$provider.$accountId.oauth';

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
  }) async {
    if (provider == 'r2') {
      try {
        final sessionToken = Supabase.instance.client.auth.currentSession?.accessToken;
        if (sessionToken != null && sessionToken.isNotEmpty) return sessionToken;
      } catch (_) {
        // Supabase can be intentionally unavailable in isolated unit tests.
      }
    }
    return _storage.read(key: _key(provider, accountId));
  }

  Future<void> writeOAuthCredential({
    required String provider,
    required String accountId,
    required CloudOAuthCredential credential,
  }) async {
    if (credential.accessToken.trim().isEmpty) {
      throw ArgumentError('OAuth access token cannot be empty.');
    }
    await _storage.write(
      key: _oauthKey(provider, accountId),
      value: jsonEncode(credential.toJson()),
    );
    await writeToken(
      provider: provider,
      accountId: accountId,
      token: credential.accessToken,
    );
  }

  Future<CloudOAuthCredential?> readOAuthCredential({
    required String provider,
    required String accountId,
  }) async {
    final raw = await _storage.read(key: _oauthKey(provider, accountId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final credential = CloudOAuthCredential.fromJson(decoded);
      return credential.accessToken.isEmpty ? null : credential;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteToken({
    required String provider,
    required String accountId,
  }) async {
    await _storage.delete(key: _key(provider, accountId));
    await _storage.delete(key: _oauthKey(provider, accountId));
  }
}
