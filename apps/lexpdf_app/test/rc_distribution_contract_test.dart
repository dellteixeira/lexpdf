import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LexPDF is versioned as the first 1.0.0 release candidate', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0-rc.1+1'));
  });

  test('release candidate distribution validates RC semver and signing gates', () {
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
      'apksigner verify',
      'flutter build appbundle --release',
      'LEXPDF_WINDOWS_CERTIFICATE_BASE64',
      'Get-AuthenticodeSignature',
      'Inno Setup',
      'LEXPDF_MACOS_CERTIFICATE_BASE64',
      'notarytool submit',
      'stapler validate',
      'SHA256SUMS-Android.txt',
      'SHA256SUMS-Windows.txt',
      'SHA256SUMS-macOS.txt',
    ]) {
      expect(workflow, contains(requiredContract));
    }
  });
}
