import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ai/ai_input_policy.dart';

void main() {
  test('normalizes whitespace and clamps item count', () {
    const policy = AiInputPolicy(maxItems: 20);
    final input = policy.prepare('  texto\n\n  de   estudo  ', 99);
    expect(input.text, 'texto de estudo');
    expect(input.itemCount, 20);
    expect(input.truncated, isFalse);
  });

  test('truncates oversized text deterministically', () {
    const policy = AiInputPolicy(maxCharacters: 10);
    final input = policy.prepare('1234567890ABC', 0);
    expect(input.text, '1234567890');
    expect(input.itemCount, 1);
    expect(input.truncated, isTrue);
  });

  test('rejects empty text', () {
    const policy = AiInputPolicy();
    expect(() => policy.prepare('   \n ', 8), throwsArgumentError);
  });
}
