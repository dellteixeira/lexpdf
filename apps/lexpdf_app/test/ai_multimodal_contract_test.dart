import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multimodal analysis is authenticated bounded and source-bound', () {
    final client =
        File('lib/src/core/ai/remote_vision_service.dart').readAsStringSync();
    final worker = File('../../backend/cloudflare/src/index.ts').readAsStringSync();
    expect(client, contains('maxImageBytes = 6 * 1024 * 1024'));
    expect(client, contains('imageBase64'));
    expect(client, contains('Bearer'));
    expect(worker, contains('/v1/ai/vision'));
    expect(worker, contains('@cf/google/gemma-4-26b-a4b-it'));
    expect(worker, contains('Descreva somente o que é sustentado pela imagem'));
    expect(worker, contains('Não invente legislação'));
  });
}
