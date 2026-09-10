import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner disables Impeller before Flutter engine startup', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains('FLUTTER_ENGINE_SWITCHES'));
    expect(source, contains('FLUTTER_ENGINE_SWITCH_1'));
    expect(source, contains('enable-impeller=false'));

    final switchIndex = source.indexOf('enable-impeller=false');
    final projectIndex = source.indexOf('flutter::DartProject project');
    expect(switchIndex, greaterThanOrEqualTo(0));
    expect(projectIndex, greaterThan(switchIndex));
  });
}
