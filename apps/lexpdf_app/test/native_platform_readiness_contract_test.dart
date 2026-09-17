import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android keeps network access without broad legacy storage permissions', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
    );
    expect(
      manifest,
      isNot(contains('android.permission.READ_EXTERNAL_STORAGE')),
    );
    expect(
      manifest,
      isNot(contains('android.permission.WRITE_EXTERNAL_STORAGE')),
    );
    expect(
      manifest,
      isNot(contains('android.permission.MANAGE_EXTERNAL_STORAGE')),
    );
  });

  test('Windows release resources retain LexPDF product identity', () {
    final resources = File('windows/runner/Runner.rc').readAsStringSync();

    expect(resources, contains('VALUE "CompanyName", "LexPDF"'));
    expect(resources, contains('VALUE "FileDescription", "LexPDF"'));
    expect(resources, contains('VALUE "ProductName", "LexPDF"'));
    expect(resources, contains('IDI_APP_ICON'));
    expect(resources, contains('FLUTTER_VERSION'));
  });
}
