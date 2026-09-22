import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_config.dart';

/// Provides a silent technical session for private LexPDF AI calls.
///
/// The user does not need to create or enter a LexPDF account. If a normal
/// Supabase session already exists it is reused; otherwise the app creates an
/// anonymous authenticated session on demand. The Worker still receives a
/// valid short-lived bearer token, so AI endpoints do not need to become public.
class AiAccessSession {
  const AiAccessSession._();

  static Future<String>? _pendingToken;

  static Future<String> bearerToken({
    BackendConfig config = BackendConfig.fromEnvironment,
  }) {
    final existing = _pendingToken;
    if (existing != null) return existing;
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
    if (!config.hasSupabase) {
      throw StateError(
        'A sessão privada da IA não está configurada neste build.',
      );
    }

    final client = Supabase.instance.client;
    final current = client.auth.currentSession?.accessToken.trim() ?? '';
    if (current.isNotEmpty) return current;

    try {
      final response = await client.auth.signInAnonymously(
        data: const {
          'lexpdf_mode': 'private_ai',
          'account_ui_required': false,
        },
      );
      final token =
          response.session?.accessToken.trim() ??
          client.auth.currentSession?.accessToken.trim() ??
          '';
      if (token.isEmpty) {
        throw StateError(
          'A sessão técnica da IA foi criada sem token de acesso.',
        );
      }
      return token;
    } on AuthException catch (error) {
      throw StateError(
        'Não foi possível iniciar a sessão privada automática da IA '
        '(\${error.message}).',
      );
    }
  }
}
