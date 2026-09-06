import 'dart:convert';
import 'dart:io';

import 'ai_engine.dart';
import 'ai_models.dart';

class RemoteAiStudyEngine implements AiStudyEngine {
  RemoteAiStudyEngine({
    required this.endpoint,
    this.bearerToken,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  final Uri endpoint;
  final String? bearerToken;
  final HttpClient _http;

  @override
  AiEngineKind get kind => AiEngineKind.remote;

  @override
  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
  }) async {
    final request = await _http.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(jsonEncode({
      'action': action.name,
      'text': text,
      'itemCount': itemCount,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: $body', uri: endpoint);
    }
    final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
    return AiStudyResult(
      action: action,
      engine: kind,
      sourceText: text,
      text: decoded['text']?.toString(),
      flashcards: ((decoded['flashcards'] as List?) ?? const [])
          .map((item) {
            final map = (item as Map).cast<String, dynamic>();
            return AiFlashcard(
              question: map['question']?.toString() ?? '',
              answer: map['answer']?.toString() ?? '',
            );
          })
          .where((item) => item.question.isNotEmpty || item.answer.isNotEmpty)
          .toList(growable: false),
      questions: ((decoded['questions'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}
