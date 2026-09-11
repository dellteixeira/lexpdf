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

  test('Windows uses accelerated Skia by default on Windows 10 and 11', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, isNot(contains('RtlGetVersion')));
    expect(source, isNot(contains('IsWindows10Build')));
    expect(source, contains('LEXPDF_FORCE_SOFTWARE_RENDERING'));
    expect(source, contains('ForceSoftwareRenderingRequested()'));
    expect(source, contains('enable-software-rendering'));
    expect(source, contains('FLUTTER_ENGINE_SWITCHES", L"2"'));
    expect(source, contains('FLUTTER_ENGINE_SWITCHES", L"1"'));

    final diagnosticGateIndex =
        source.indexOf('if (ForceSoftwareRenderingRequested())');
    final softwareIndex = source.indexOf('enable-software-rendering');
    final defaultSkiaIndex = source.lastIndexOf('FLUTTER_ENGINE_SWITCHES", L"1"');
    final configureIndex = source.indexOf('ConfigureWindowsRenderer();');
    final projectIndex = source.indexOf('flutter::DartProject project');

    expect(diagnosticGateIndex, greaterThanOrEqualTo(0));
    expect(softwareIndex, greaterThan(diagnosticGateIndex));
    expect(defaultSkiaIndex, greaterThan(softwareIndex));
    expect(configureIndex, greaterThanOrEqualTo(0));
    expect(projectIndex, greaterThan(configureIndex));
  });
}
