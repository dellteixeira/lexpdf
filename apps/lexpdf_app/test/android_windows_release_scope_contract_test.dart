import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release candidate scope is Android and Windows only', () {
    final hardening =
        File('../../.github/workflows/release-hardening.yml').readAsStringSync();
    final distribution =
        File('../../.github/workflows/beta-distribution.yml').readAsStringSync();
    final policy =
        File('tool/verify_release_platform_scope.sh').readAsStringSync();
    expect(hardening, contains('android-release:'));
    expect(hardening, contains('windows-release:'));
    expect(distribution, contains('android-signed:'));
    expect(distribution, contains('windows-installer:'));
    expect(distribution, contains('RC_MANIFEST_ANDROID.json'));
    expect(distribution, contains('RC_MANIFEST_WINDOWS.json'));
    expect(policy, contains('Android + Windows only'));
    const retiredDesktop = 'mac' 'os';
    const retiredMobile = 'i' 'os';
    expect(hardening, isNot(contains('runs-on: $retiredDesktop')));
    expect(distribution, isNot(contains('runs-on: $retiredDesktop')));
    expect(hardening, isNot(contains('flutter build $retiredMobile')));
    expect(distribution, isNot(contains('flutter build $retiredMobile')));
  });
}
