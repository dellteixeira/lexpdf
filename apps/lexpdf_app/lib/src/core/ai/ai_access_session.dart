import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../backend/backend_config.dart';

/// Provides an installation-scoped technical credential for private LexPDF AI.
///
/// This is deliberately not a user account. The app creates one random opaque
/// installation token, keeps it in secure storage, and reuses it for every AI
/// request. The Cloudflare Worker hashes the token and uses only that hash for
/// rate/quota accounting.
///
/// Result: the user never has to sign in just to use AI. LexPDF Cloud and other
/// account-bound features remain separate and may still require a real account.
class AiAccessSession {
  const AiAccessSession._();

  static const _storageKey = 'lexpdf_ai_install_token_v1';
  static const _prefix = 'lexpdf-install-v1.';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String>? _pendingToken;
  static String? _processToken;

  static Future<String> bearerToken({
    BackendConfig config = BackendConfig.fromEnvironment,
  }) {
    final cached = _processToken;
    if (cached != null && cached.isNotEmpty) {
      return Future<String>.value(cached);
    }

    final pending = _pendingToken;
    if (pending != null) return pending;

    final future = _resolveToken(config);
    _pendingToken = future;
    return future.whenComplete(() {
      if (identical(_pendingToken, future)) {
        _pendingToken = null;
      }
    });
  }

  static Future<String> _resolveToken(BackendConfig config) async {
    if (!config.hasAiGateway) {
      throw StateError('O gateway de IA não está configurado neste build.');
    }

    try {
      final stored = (await _storage.read(key: _storageKey))?.trim() ?? '';
      if (_isValid(stored)) {
        _processToken = stored;
        return stored;
      }
    } catch (_) {
      // Secure storage can be temporarily unavailable on some desktop/mobile
      // setups. A process token still keeps AI usable for the current session.
    }

    final token = _newInstallationToken();
    _processToken = token;
    try {
      await _storage.write(key: _storageKey, value: token);
    } catch (_) {
      // Do not block AI because persistence failed. A fresh installation token
      // can be created on the next app launch.
    }
    return token;
  }

  static bool _isValid(String value) {
    if (!value.startsWith(_prefix)) return false;
    final opaque = value.substring(_prefix.length);
    return RegExp(r'^[A-Za-z0-9_-]{40,80}$').hasMatch(opaque);
  }

  static String _newInstallationToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final opaque = base64Url.encode(bytes).replaceAll('=', '');
    return '$_prefix$opaque';
  }
}
