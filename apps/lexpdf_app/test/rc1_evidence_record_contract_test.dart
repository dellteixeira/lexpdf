import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC1 evidence record stays explicit and promotion-blocking', () async {
    final evidence = await File('../../docs/RC1_EVIDENCE.md').readAsString();

    expect(evidence, contains('Candidate version: `1.0.0-rc.1+1`'));
    expect(evidence, contains('Candidate source SHA: `PENDING`'));
    expect(evidence, contains('Release Candidate Distribution run ID: `PENDING`'));
    expect(evidence, contains('apksigner verify --verbose --print-certs'));
    expect(evidence, contains('Windows signing mode (`signed` or `unsigned`)'));
    expect(evidence, contains('Executable Authenticode status'));
    expect(evidence, contains('Installer Authenticode status'));
    expect(evidence, contains('WINDOWS_SIGNING_STATUS.txt'));
    expect(evidence, contains('Observed time to first usable rendered page'));
    expect(evidence, contains('Gray-screen occurrence'));
    expect(evidence, contains('Image-heavy PDF'));
    expect(evidence, contains('RC2 required'));
    expect(evidence, contains('Stable promotion remains blocked until:'));
    expect(evidence, contains('Stable Promotion Gate succeeds'));
    expect(evidence, contains('Android + Windows'));
    expect(evidence, isNot(contains('Notarytool result / submission ID')));
    expect(evidence, isNot(contains('Stapler validation')));
    expect(evidence, isNot(contains('Gatekeeper assessment')));
  });
}
