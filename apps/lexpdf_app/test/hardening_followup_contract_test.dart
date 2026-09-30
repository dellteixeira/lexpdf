import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TXT import does not silently replace malformed UTF-8 characters', () {
    final service = File(
      'lib/src/core/notebook/notebook_document_file_service.dart',
    ).readAsStringSync();

    expect(service, contains('utf8.decode(bytes, allowMalformed: false)'));
    expect(service, contains('const cp1252 = <int, int>'));
    expect(service, isNot(contains('allowMalformed: true')));
  });
}
