import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online AI acquires a silent anonymous technical session', () {
    final access =
        File('lib/src/core/ai/ai_access_session.dart').readAsStringSync();
    final selected =
        File('lib/src/screens/ai_selection_explanation_screen.dart')
            .readAsStringSync();
    final advanced =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final study =
        File('lib/src/screens/ai_study_screen.dart').readAsStringSync();

    expect(access, contains('signInAnonymously'));
    expect(access, contains('private_ai'));
    expect(access, contains('currentSession?.accessToken'));
    expect(selected, contains('AiAccessSession.bearerToken'));
    expect(advanced, contains('AiAccessSession.bearerToken'));
    expect(workspace, contains('AiAccessSession.bearerToken'));
    expect(study, contains('AiAccessSession.bearerToken'));

    final combined = [selected, advanced, workspace, study].join('\n');
    expect(combined, isNot(contains('Entre na sua conta LexPDF para usar a IA')));
    expect(combined, isNot(contains('autenticação LexPDF')));
  });

  test('anonymous AI session is not presented as a user account', () {
    final account =
        File('lib/src/screens/account_screen.dart').readAsStringSync();

    expect(account, contains('A IA não exige conta'));
    expect(account, contains("accountUser?.email?.trim().isNotEmpty != true"));
    expect(account, contains("sessionUser?.email?.trim().isNotEmpty == true"));
    expect(account, contains('Login é necessário apenas para'));
  });
}
