import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LexPDF is versioned as the first 1.0.0 release candidate', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0-rc.1+1'));
  });

  test('release candidate distribution validates Android and Windows policy', () {
    final workflow = File(
      '../../.github/workflows/beta-distribution.yml',
    ).readAsStringSync();

    expect(workflow, contains('name: Release Candidate Distribution'));
    expect(
      workflow,
      contains(r"^1\.0\.0-rc\.[1-9][0-9]*\+[1-9][0-9]*$"),
    );

    for (final requiredContract in <String>[
      'LEXPDF_ANDROID_KEYSTORE_BASE64',
      'apksigner_path',
      'flutter build appbundle --release',
      'LEXPDF_WINDOWS_CERTIFICATE_BASE64',
      'WINDOWS_SIGNING_ENABLED',
      'Get-AuthenticodeSignature',
      'X509Store',
      "'Root'",
      "'TrustedPublisher'",
      'StoreLocation]::CurrentUser',
      'Inno Setup',
      'WINDOWS_SIGNING_STATUS.txt',
      'SHA256SUMS-Android.txt',
      'SHA256SUMS-Windows.txt',
    ]) {
      expect(workflow, contains(requiredContract));
    }

    expect(workflow, isNot(contains('Import-Certificate -FilePath')));
    expect(workflow, isNot(contains('macos-dmg:')));
    expect(workflow, isNot(contains('LEXPDF_MACOS_CERTIFICATE_BASE64')));
    expect(workflow, isNot(contains('notarytool submit')));
  });
}
