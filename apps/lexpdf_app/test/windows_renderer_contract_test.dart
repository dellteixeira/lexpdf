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

  test('Windows 10 uses software rendering without changing Windows 11', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains('RtlGetVersion'));
    expect(source, contains('dwMajorVersion == 10'));
    expect(source, contains('dwBuildNumber < 22000'));
    expect(source, contains('IsWindows10Build()'));
    expect(source, contains('FLUTTER_ENGINE_SWITCH_2'));
    expect(source, contains('enable-software-rendering'));
    expect(source, contains('FLUTTER_ENGINE_SWITCHES", L"2"'));
    expect(source, contains('FLUTTER_ENGINE_SWITCHES", L"1"'));

    final configureIndex = source.indexOf('ConfigureWindowsRenderer();');
    final projectIndex = source.indexOf('flutter::DartProject project');
    expect(configureIndex, greaterThanOrEqualTo(0));
    expect(projectIndex, greaterThan(configureIndex));
  });
}
