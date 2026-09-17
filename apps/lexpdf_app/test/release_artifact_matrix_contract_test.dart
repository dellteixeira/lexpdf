import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release hardening smoke-checks Android artifact contents', () {
    final workflow = File('../../.github/workflows/release-hardening.yml')
        .readAsStringSync();

    expect(workflow, contains('Smoke-check Android release artifact'));
    expect(workflow, contains("apk='build/app/outputs/flutter-apk/app-release.apk'"));
    expect(workflow, contains("grep -q 'AndroidManifest.xml'"));
    expect(workflow, contains("grep -q 'classes.dex'"));
    expect(workflow, contains("grep -q 'lib/arm64-v8a/libapp.so'"));
    expect(workflow, contains(r'sha256sum "$apk"'));
  });

  test('release hardening publishes a smaller ARM64 Android artifact', () {
    final workflow = File('../../.github/workflows/release-hardening.yml')
        .readAsStringSync();

    expect(workflow, contains('flutter build apk --release --split-per-abi'));
    expect(workflow, contains('app-arm64-v8a-release.apk'));
    expect(workflow, contains('ANDROID_TARGET_SDK_ARM64.txt'));
    expect(workflow, contains('name: lexpdf-android-arm64'));
    expect(workflow, contains('ARM64 APK must be smaller than the universal APK.'));
  });

  test('release hardening smoke-checks Windows release bundle', () {
    final workflow = File('../../.github/workflows/release-hardening.yml')
        .readAsStringSync();

    expect(workflow, contains('Smoke-check Windows release artifact'));
    expect(workflow, contains("'lexpdf_app.exe'"));
    expect(workflow, contains("'flutter_windows.dll'"));
    expect(workflow, contains("'data/flutter_assets'"));
    expect(workflow, contains(r'Get-FileHash $exe -Algorithm SHA256'));
  });
}
