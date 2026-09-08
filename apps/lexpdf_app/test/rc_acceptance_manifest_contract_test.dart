import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC1 acceptance manifest keeps signed artifact requirements', () {
    final manifest = File('../../docs/RC1_ACCEPTANCE.md').readAsStringSync();

    expect(manifest, contains('1.0.0-rc.1+1'));
    expect(manifest, contains('Signed release APK produced.'));
    expect(manifest, contains('Signed release AAB produced.'));
    expect(manifest, contains('Authenticode signature for executable is `Valid`.'));
    expect(manifest, contains('Authenticode signature for installer is `Valid`.'));
    expect(manifest, contains('Apple notarization succeeds.'));
    expect(manifest, contains('Stapler validation succeeds.'));
    expect(manifest, contains('SHA-256'));
  });

  test('RC1 acceptance manifest requires real native runtime evidence', () {
    final manifest = File('../../docs/RC1_ACCEPTANCE.md').readAsStringSync();

    expect(manifest, contains('1600+ page PDF opens in the actual pdfrx viewer.'));
    expect(manifest, contains('First usable page appears without gray-screen deadlock.'));
    expect(manifest, contains('Continuous zoom remains stable.'));
    expect(manifest, contains('Background/resume does not corrupt reader state.'));
    expect(manifest, contains('No unbounded memory growth observed'));
    expect(manifest, contains('Image-heavy PDF validated separately'));
    expect(manifest, contains('observed time to first usable rendered page'));
    expect(manifest, contains('representative RAM/RSS/working-set measurement'));
  });

  test('RC1 promotion rule forbids stable release with unresolved blockers', () {
    final manifest = File('../../docs/RC1_ACCEPTANCE.md').readAsStringSync();

    expect(manifest, contains('no open blocker or critical defect remains'));
    expect(manifest, contains('all release artifacts come from the same accepted candidate source'));
    expect(manifest, contains('final regression passes after any RC fix'));
  });
}
