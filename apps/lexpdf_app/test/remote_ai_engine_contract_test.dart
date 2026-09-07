import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ai/ai_input_policy.dart';
import 'package:lexpdf_app/src/core/ai/remote_ai_engine.dart';

void main() {
  test('remote AI policy can enforce a stricter source bound', () {
    const policy = AiInputPolicy(maxCharacters: 5, maxItems: 3);
    final input = policy.prepare('abcdef', 10);
    expect(input.text, 'abcde');
    expect(input.itemCount, 3);
    expect(input.truncated, isTrue);
  });

  test('remote AI accepts HTTPS endpoints', () {
    final engine = RemoteAiStudyEngine(
      endpoint: Uri.parse('https://ai.example.test/v1/study'),
    );
    expect(engine.endpoint.scheme, 'https');
    expect(engine.endpoint.host, 'ai.example.test');
  });

  test('remote AI rejects plaintext HTTP before any request is created', () {
    expect(
      () => RemoteAiStudyEngine(
        endpoint: Uri.parse('http://ai.example.test/v1/study'),
      ),
      throwsArgumentError,
    );
  });

  test('remote AI rejects credentials embedded in the endpoint URL', () {
    expect(
      () => RemoteAiStudyEngine(
        endpoint: Uri.parse('https://user:secret@ai.example.test/v1/study'),
      ),
      throwsArgumentError,
    );
  });
}
