import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository-owned product surfaces contain only active platform targets', () {
    final retiredPatterns = <RegExp>[
      RegExp(r'\b' + 'mac' 'os' + r'\b', caseSensitive: false),
      RegExp(r'\b' + 'i' 'os' + r'\b', caseSensitive: false),
      RegExp(r'\b' + 'i' 'pad' 'os' + r'\b', caseSensitive: false),
      RegExp(r'\b' + 'i' 'cloud' + r'\b', caseSensitive: false),
      RegExp(
        r'\b' + 'apple' + r'\s+' + 'file' + r'\s+' + 'provider' + r'\b',
        caseSensitive: false,
      ),
    ];

    const retiredDesktopDirectory = 'mac' 'os';
    const retiredMobileDirectory = 'i' 'os';
    expect(Directory(retiredDesktopDirectory).existsSync(), isFalse);
    expect(Directory(retiredMobileDirectory).existsSync(), isFalse);

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
        _scanFile(root, retiredPatterns, violations);
      } else if (root is Directory && root.existsSync()) {
        for (final entity in root.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            _scanFile(entity, retiredPatterns, violations);
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

void _scanFile(
  File file,
  List<RegExp> retiredPatterns,
  List<String> violations,
) {
  const textExtensions = <String>{
    '.dart',
    '.md',
    '.yml',
    '.yaml',
    '.json',
    '.txt',
  };
  final path = file.path.toLowerCase();
  if (!textExtensions.any(path.endsWith)) return;

  final content = file.readAsStringSync();
  if (retiredPatterns.any((pattern) => pattern.hasMatch(content))) {
    violations.add(file.path);
  }
}
