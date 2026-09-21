import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AiVisionResult {
  const AiVisionResult({
    required this.text,
    required this.model,
    this.quotaRemaining,
    this.quotaLimit,
  });
  final String text;
  final String model;
  final int? quotaRemaining;
  final int? quotaLimit;
}

class RemoteAiVisionService {
  RemoteAiVisionService({
    required Uri endpoint,
    this.bearerToken,
    HttpClient? httpClient,
  })  : endpoint = _validated(endpoint),
        _http = httpClient ?? HttpClient();

  static const int maxImageBytes = 6 * 1024 * 1024;
  static const int maxPromptCharacters = 4000;
  final Uri endpoint;
  final String? bearerToken;
  final HttpClient _http;

  static Uri _validated(Uri endpoint) {
    if (endpoint.scheme.toLowerCase() != 'https' ||
        endpoint.host.trim().isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw ArgumentError('Vision endpoint must be credential-free HTTPS.');
    }
    return endpoint;
  }

  Future<AiVisionResult> analyze({
    required Uint8List imageBytes,
    required String mimeType,
    required String prompt,
  }) async {
    if (imageBytes.isEmpty || imageBytes.length > maxImageBytes) {
      throw ArgumentError('Imagem deve ter entre 1 byte e 6 MB.');
    }
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty || cleanPrompt.length > maxPromptCharacters) {
      throw ArgumentError('Prompt visual inválido.');
    }
    const accepted = {'image/png', 'image/jpeg', 'image/webp'};
    if (!accepted.contains(mimeType)) {
      throw ArgumentError('Formato visual não suportado: $mimeType');
    }
    final request = await _http.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(jsonEncode({
      'imageBase64': base64Encode(imageBytes),
      'mimeType': mimeType,
      'prompt': cleanPrompt,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw StateError('Entre na sua conta LexPDF para usar análise visual.');
      }
      if (response.statusCode == 429) {
        throw StateError('Limite temporário de IA visual atingido.');
      }
      throw HttpException('${response.statusCode}: $body', uri: endpoint);
    }
    final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
    final text = decoded['text']?.toString().trim() ?? '';
    if (text.isEmpty) throw StateError('A IA visual retornou resposta vazia.');
    final quota = decoded['quota'] is Map
        ? (decoded['quota'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return AiVisionResult(
      text: text,
      model: decoded['model']?.toString() ?? '',
      quotaRemaining: _asInt(quota['creditsRemaining']),
      quotaLimit: _asInt(quota['dailyCreditLimit']),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
