import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ai/ai_input_policy.dart';

void main() {
  test('remote AI policy can enforce a stricter source bound', () {
    const policy = AiInputPolicy(maxCharacters: 5, maxItems: 3);
    final input = policy.prepare('abcdef', 10);
    expect(input.text, 'abcde');
    expect(input.itemCount, 3);
    expect(input.truncated, isTrue);
  });
}
