import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'cloud_credential_store.dart';

class CloudOAuthConfig {
  const CloudOAuthConfig({
    required this.googleClientId,
    required this.microsoftClientId,
    this.microsoftTenant = 'common',
    this.callbackScheme = 'lexpdf',
  });

  final String googleClientId;
  final String microsoftClientId;
  final String microsoftTenant;
  final String callbackScheme;

  static const fromEnvironment = CloudOAuthConfig(
    googleClientId: String.fromEnvironment('LEXPDF_GOOGLE_CLIENT_ID'),
    microsoftClientId: String.fromEnvironment('LEXPDF_MICROSOFT_CLIENT_ID'),
    microsoftTenant: String.fromEnvironment(
      'LEXPDF_MICROSOFT_TENANT',
      defaultValue: 'common',
    ),
    callbackScheme: String.fromEnvironment(
      'LEXPDF_OAUTH_CALLBACK_SCHEME',
      defaultValue: 'lexpdf',
    ),
  );
}

class CloudOAuthService {
  CloudOAuthService({
    this.config = CloudOAuthConfig.fromEnvironment,
    this.credentials = const CloudCredentialStore(),
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  final CloudOAuthConfig config;
  final CloudCredentialStore credentials;
  final HttpClient _http;

  bool get googleConfigured => config.googleClientId.trim().isNotEmpty;
  bool get microsoftConfigured => config.microsoftClientId.trim().isNotEmpty;

  Future<void> connectGoogleDrive({required String accountId}) async {
    if (!googleConfigured) {
      throw StateError('LEXPDF_GOOGLE_CLIENT_ID is not configured.');
    }
    final verifier = _randomVerifier();
    final challenge = _challenge(verifier);
    final redirectUri = '${config.callbackScheme}:/oauth2redirect';
    final auth = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': config.googleClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email https://www.googleapis.com/auth/drive',
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    final result = await FlutterWebAuth2.authenticate(
      url: auth.toString(),
      callbackUrlScheme: config.callbackScheme,
    );
    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) throw StateError('Google OAuth returned no code.');
    final token = await _exchangeForm(
      Uri.parse('https://oauth2.googleapis.com/token'),
      {
        'client_id': config.googleClientId,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );
    final accessToken = token['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Google OAuth returned no access token.');
    }
    await credentials.writeToken(
      provider: 'google_drive',
      accountId: accountId,
      token: accessToken,
    );
  }

  Future<void> connectOneDrive({required String accountId}) async {
    if (!microsoftConfigured) {
      throw StateError('LEXPDF_MICROSOFT_CLIENT_ID is not configured.');
    }
    final verifier = _randomVerifier();
    final challenge = _challenge(verifier);
    final redirectUri = '${config.callbackScheme}:/oauth2redirect';
    final tenant = Uri.encodeComponent(config.microsoftTenant);
    final auth = Uri.parse(
      'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize',
    ).replace(queryParameters: {
      'client_id': config.microsoftClientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'response_mode': 'query',
      'scope': 'openid profile offline_access Files.ReadWrite',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    final result = await FlutterWebAuth2.authenticate(
      url: auth.toString(),
      callbackUrlScheme: config.callbackScheme,
    );
    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) throw StateError('Microsoft OAuth returned no code.');
    final token = await _exchangeForm(
      Uri.parse('https://login.microsoftonline.com/$tenant/oauth2/v2.0/token'),
      {
        'client_id': config.microsoftClientId,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
        'scope': 'openid profile offline_access Files.ReadWrite',
      },
    );
    final accessToken = token['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Microsoft OAuth returned no access token.');
    }
    await credentials.writeToken(
      provider: 'onedrive',
      accountId: accountId,
      token: accessToken,
    );
  }

  Future<Map<String, dynamic>> _exchangeForm(
    Uri uri,
    Map<String, String> fields,
  ) async {
    final request = await _http.postUrl(uri);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(fields.entries
        .map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&'));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: $body', uri: uri);
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  static String _randomVerifier() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static String _challenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }
}
