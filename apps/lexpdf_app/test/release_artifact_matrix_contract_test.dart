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
    expect(workflow, contains('sha256sum "$apk"'));
  });

  test('release hardening smoke-checks Windows release bundle', () {
    final workflow = File('../../.github/workflows/release-hardening.yml')
        .readAsStringSync();

    expect(workflow, contains('Smoke-check Windows release artifact'));
    expect(workflow, contains("'lexpdf_app.exe'"));
    expect(workflow, contains("'flutter_windows.dll'"));
    expect(workflow, contains("'data/flutter_assets'"));
    expect(workflow, contains('Get-FileHash $exe -Algorithm SHA256'));
  });

  test('release hardening smoke-checks macOS app identity', () {
    final workflow = File('../../.github/workflows/release-hardening.yml')
        .readAsStringSync();

    expect(workflow, contains('Smoke-check macOS release artifact'));
    expect(workflow, contains("app='build/macos/Build/Products/Release/LexPDF.app'"));
    expect(workflow, contains('Contents/MacOS/LexPDF'));
    expect(workflow, contains('Contents/Info.plist'));
    expect(workflow, contains("grep -qx 'com.lexpdf.lexpdfApp'"));
    expect(workflow, contains('shasum -a 256 "$executable"'));
  });
}
