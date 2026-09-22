import 'dart:convert';
import 'dart:io';

import 'ai_engine.dart';
import 'ai_input_policy.dart';
import 'ai_models.dart';

class RemoteAiStudyEngine implements AiStudyEngine {
  RemoteAiStudyEngine({
    required Uri endpoint,
    this.bearerToken,
    this.inputPolicy = const AiInputPolicy(maxCharacters: 12000),
    HttpClient? httpClient,
  })  : endpoint = _validatedEndpoint(endpoint),
        _http = httpClient ?? HttpClient();

  final Uri endpoint;
  final String? bearerToken;
  final AiInputPolicy inputPolicy;
  final HttpClient _http;

  static Uri _validatedEndpoint(Uri endpoint) {
    if (endpoint.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote AI endpoints must use HTTPS.',
      );
    }
    if (endpoint.host.trim().isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote AI endpoint must include a host.',
      );
    }
    if (endpoint.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote AI endpoint must not embed credentials in the URL.',
      );
    }
    return endpoint;
  }

  @override
  AiEngineKind get kind => AiEngineKind.remote;

  @override
  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
    AiExplanationDepth explanationDepth = AiExplanationDepth.detailed,
  }) =>
      runExplanation(
        action: action,
        text: text,
        itemCount: itemCount,
        explanationDepth: explanationDepth,
      );

  Future<AiStudyResult> runExplanation({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
    AiExplanationDepth explanationDepth = AiExplanationDepth.detailed,
    AiExplanationIntent intent = AiExplanationIntent.explain,
  }) async {
    final input = inputPolicy.prepare(text, itemCount);
    final request = await _http.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(jsonEncode({
      'action': action.name,
      'text': input.text,
      'itemCount': input.itemCount,
      'depth': explanationDepth.name,
      'intent': intent.name,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw StateError('A sessão privada da IA expirou. Tente novamente.');
      }
      if (response.statusCode == 429) {
        throw StateError(
          'Limite temporário da IA atingido. Aguarde um pouco ou tente novamente amanhã.',
        );
      }
      throw HttpException('${response.statusCode}: $body', uri: endpoint);
    }
    final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
    final quota = decoded['quota'] is Map
        ? (decoded['quota'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return AiStudyResult(
      action: action,
      engine: kind,
      sourceText: input.text,
      text: decoded['text']?.toString(),
      explanationDepth: explanationDepth,
      model: decoded['model']?.toString(),
      fallbackUsed: decoded['fallbackUsed'] == true,
      quotaRemaining: _asInt(quota['creditsRemaining']),
      quotaLimit: _asInt(quota['dailyCreditLimit']),
      flashcards: ((decoded['flashcards'] as List?) ?? const [])
          .map((item) {
            final map = (item as Map).cast<String, dynamic>();
            return AiFlashcard(
              question: map['question']?.toString() ?? '',
              answer: map['answer']?.toString() ?? '',
            );
          })
          .where((item) => item.question.isNotEmpty || item.answer.isNotEmpty)
          .take(input.itemCount)
          .toList(growable: false),
      questions: ((decoded['questions'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .take(input.itemCount)
          .toList(growable: false),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
