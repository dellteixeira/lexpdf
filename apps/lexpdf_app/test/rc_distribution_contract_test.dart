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
      'flutter build apk --release --split-per-abi',
      'app-arm64-v8a-release.apk',
      'app-armeabi-v7a-release.apk',
      'app-x86_64-release.apk',
      'ANDROID_ARTIFACT_SIZES.txt',
      'apksigner_path',
      'flutter build appbundle --release',
      'LEXPDF_WINDOWS_CERTIFICATE_BASE64',
      'WINDOWS_SIGNING_ENABLED',
      'EXPECTED_WINDOWS_SIGNER_THUMBPRINT',
      'Get-AuthenticodeSignature',
      'SignerCertificate',
      'signed-self-signed',
      'executable_signer_match=true',
      'installer_signer_match=true',
      'public_trust=false',
      'Inno Setup',
      'WINDOWS_SIGNING_STATUS.txt',
      'SHA256SUMS-Android.txt',
      'SHA256SUMS-Windows.txt',
    ]) {
      expect(workflow, contains(requiredContract));
    }

    expect(workflow, isNot(contains("apk='build/app/outputs/flutter-apk/app-release.apk'")));
    expect(workflow, isNot(contains('Import-Certificate -FilePath')));
    expect(workflow, isNot(contains('X509Store]::new')));
    expect(workflow, isNot(contains("'Root'")));
    expect(workflow, isNot(contains("'TrustedPublisher'")));
    expect(workflow, isNot(contains('macos-dmg:')));
    expect(workflow, isNot(contains('LEXPDF_MACOS_CERTIFICATE_BASE64')));
    expect(workflow, isNot(contains('notarytool submit')));
  });
}
