import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/cloud/cloud_oauth_service.dart';

void main() {
  const state = 'expected-state-token';

  test('accepts callback only when scheme, path and state match', () {
    final code = OAuthCallbackValidator.authorizationCode(
      callbackUrl: 'lexpdf:/oauth2redirect?code=abc123&state=$state',
      expectedState: state,
      expectedScheme: 'lexpdf',
      providerLabel: 'Google',
    );

    expect(code, 'abc123');
  });

  test('rejects callback with missing or mismatched state', () {
    expect(
      () => OAuthCallbackValidator.authorizationCode(
        callbackUrl: 'lexpdf:/oauth2redirect?code=abc123',
        expectedState: state,
        expectedScheme: 'lexpdf',
        providerLabel: 'Google',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => OAuthCallbackValidator.authorizationCode(
        callbackUrl: 'lexpdf:/oauth2redirect?code=abc123&state=attacker-state',
        expectedState: state,
        expectedScheme: 'lexpdf',
        providerLabel: 'Microsoft',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects callbacks outside the registered redirect URI', () {
    expect(
      () => OAuthCallbackValidator.authorizationCode(
        callbackUrl: 'other:/oauth2redirect?code=abc123&state=$state',
        expectedState: state,
        expectedScheme: 'lexpdf',
        providerLabel: 'Google',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => OAuthCallbackValidator.authorizationCode(
        callbackUrl: 'lexpdf:/wrong?code=abc123&state=$state',
        expectedState: state,
        expectedScheme: 'lexpdf',
        providerLabel: 'Microsoft',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('surfaces provider OAuth errors before accepting a code', () {
    expect(
      () => OAuthCallbackValidator.authorizationCode(
        callbackUrl:
            'lexpdf:/oauth2redirect?error=access_denied&error_description=cancelled&state=$state',
        expectedState: state,
        expectedScheme: 'lexpdf',
        providerLabel: 'Google',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('Google and Microsoft authorization requests bind a state value', () async {
    final source =
        await File('lib/src/core/cloud/cloud_oauth_service.dart').readAsString();

    expect(RegExp("'state': state").allMatches(source).length, 2);
    expect(source, contains('final state = _randomState();'));
    expect(source, contains('expectedState: state'));
    expect(source, contains('OAuthCallbackValidator.authorizationCode'));
  });
}
