import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository-owned product surfaces contain only active platform targets', () {
    const retiredPlatform = 'mac' 'os';

    expect(Directory(retiredPlatform).existsSync(), isFalse);

    final roots = <FileSystemEntity>[
      File('../../README.md'),
      File('../../ARCHITECTURE.md'),
      Directory('../../docs'),
      Directory('../../.github/workflows'),
      Directory('lib'),
      Directory('test'),
    ];

    final violations = <String>[];
    for (final root in roots) {
      if (root is File) {
        _scanFile(root, retiredPlatform, violations);
      } else if (root is Directory && root.existsSync()) {
        for (final entity in root.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            _scanFile(entity, retiredPlatform, violations);
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Retired platform references: ${violations.join(', ')}',
    );
  });
}

void _scanFile(File file, String retiredPlatform, List<String> violations) {
  const textExtensions = <String>{'.dart', '.md', '.yml', '.yaml', '.json', '.txt'};
  final path = file.path.toLowerCase();
  if (!textExtensions.any(path.endsWith)) return;

  final content = file.readAsStringSync().toLowerCase();
  if (content.contains(retiredPlatform)) {
    violations.add(file.path);
  }
}
