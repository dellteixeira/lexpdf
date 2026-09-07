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

class OAuthCallbackValidator {
  const OAuthCallbackValidator._();

  static String authorizationCode({
    required String callbackUrl,
    required String expectedState,
    required String expectedScheme,
    required String providerLabel,
  }) {
    final uri = Uri.parse(callbackUrl);
    if (uri.scheme != expectedScheme || uri.path != '/oauth2redirect') {
      throw StateError('$providerLabel OAuth returned an unexpected callback URI.');
    }

    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final description = uri.queryParameters['error_description'];
      throw StateError(
        description == null || description.isEmpty
            ? '$providerLabel OAuth failed: $error.'
            : '$providerLabel OAuth failed: $error ($description).',
      );
    }

    final returnedState = uri.queryParameters['state'];
    if (returnedState == null ||
        !_constantTimeEquals(returnedState, expectedState)) {
      throw StateError('$providerLabel OAuth state validation failed.');
    }

    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('$providerLabel OAuth returned no code.');
    }
    return code;
  }

  static bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var difference = leftBytes.length ^ rightBytes.length;
    final maxLength = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var index = 0; index < maxLength; index++) {
      final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
      final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
      difference |= leftByte ^ rightByte;
    }
    return difference == 0;
  }
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
    final state = _randomState();
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
      'state': state,
    });
    final result = await FlutterWebAuth2.authenticate(
      url: auth.toString(),
      callbackUrlScheme: config.callbackScheme,
    );
    final code = OAuthCallbackValidator.authorizationCode(
      callbackUrl: result,
      expectedState: state,
      expectedScheme: config.callbackScheme,
      providerLabel: 'Google',
    );
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
    await _saveCredential('google_drive', accountId, token);
  }

  Future<void> connectOneDrive({required String accountId}) async {
    if (!microsoftConfigured) {
      throw StateError('LEXPDF_MICROSOFT_CLIENT_ID is not configured.');
    }
    final verifier = _randomVerifier();
    final challenge = _challenge(verifier);
    final state = _randomState();
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
      'state': state,
    });
    final result = await FlutterWebAuth2.authenticate(
      url: auth.toString(),
      callbackUrlScheme: config.callbackScheme,
    );
    final code = OAuthCallbackValidator.authorizationCode(
      callbackUrl: result,
      expectedState: state,
      expectedScheme: config.callbackScheme,
      providerLabel: 'Microsoft',
    );
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
    await _saveCredential('onedrive', accountId, token);
  }

  Future<String> validAccessToken({
    required String provider,
    required String accountId,
  }) async {
    final oauth = await credentials.readOAuthCredential(
      provider: provider,
      accountId: accountId,
    );
    if (oauth == null) {
      final legacy = await credentials.readToken(
        provider: provider,
        accountId: accountId,
      );
      if (legacy == null || legacy.isEmpty) {
        throw StateError('$provider/$accountId is not authenticated.');
      }
      return legacy;
    }
    if (!oauth.isExpired) return oauth.accessToken;
    final refreshToken = oauth.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('$provider/$accountId needs to be reconnected.');
    }

    final refreshed = switch (provider) {
      'google_drive' => await _exchangeForm(
          Uri.parse('https://oauth2.googleapis.com/token'),
          {
            'client_id': config.googleClientId,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          },
        ),
      'onedrive' => await _exchangeForm(
          Uri.parse(
            'https://login.microsoftonline.com/${Uri.encodeComponent(config.microsoftTenant)}/oauth2/v2.0/token',
          ),
          {
            'client_id': config.microsoftClientId,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
            'scope': 'openid profile offline_access Files.ReadWrite',
          },
        ),
      _ => throw StateError('OAuth refresh is not supported for $provider.'),
    };
    await _saveCredential(
      provider,
      accountId,
      refreshed,
      fallbackRefreshToken: refreshToken,
    );
    final updated = await credentials.readOAuthCredential(
      provider: provider,
      accountId: accountId,
    );
    if (updated == null || updated.accessToken.isEmpty) {
      throw StateError('OAuth refresh did not return a usable access token.');
    }
    return updated.accessToken;
  }

  Future<void> _saveCredential(
    String provider,
    String accountId,
    Map<String, dynamic> token, {
    String? fallbackRefreshToken,
  }) async {
    final accessToken = token['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('$provider OAuth returned no access token.');
    }
    final expiresIn = (token['expires_in'] as num?)?.toInt();
    final expiresAt = expiresIn == null
        ? null
        : DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    await credentials.writeOAuthCredential(
      provider: provider,
      accountId: accountId,
      credential: CloudOAuthCredential(
        accessToken: accessToken,
        refreshToken:
            token['refresh_token']?.toString() ?? fallbackRefreshToken,
        expiresAt: expiresAt,
      ),
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
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&'));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: $body', uri: uri);
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  static String _randomVerifier() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _challenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }
}
