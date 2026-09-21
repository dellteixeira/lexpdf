import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/generate_release_manifest.dart' as manifest;

void main() {
  test('release manifest generator accepts Android artifacts', () async {
    final root = await Directory.systemTemp.createTemp('lexpdf-manifest-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final artifact = File('${root.path}${Platform.pathSeparator}artifact.bin');
    await artifact.writeAsBytes([1, 2, 3, 4]);
    final output = File('${root.path}${Platform.pathSeparator}manifest.json');
    await manifest.main([
      '--platform', 'android',
      '--version', '1.0.0-rc.1',
      '--output', output.path,
      artifact.path,
    ]);
    final decoded =
        jsonDecode(await output.readAsString()) as Map<String, dynamic>;
    expect(decoded['schema'], 'lexpdf-release-manifest-v1');
    expect(decoded['platform'], 'android');
    expect((decoded['artifacts'] as List).single['sha256'], isNotEmpty);
  });
}
