import 'dart:convert';
import 'dart:io';

class AiEmbeddingBatch {
  const AiEmbeddingBatch({
    required this.vectors,
    required this.model,
    this.quotaRemaining,
    this.quotaLimit,
  });

  final List<List<double>> vectors;
  final String model;
  final int? quotaRemaining;
  final int? quotaLimit;
}

class RemoteAiEmbeddingService {
  RemoteAiEmbeddingService({
    required Uri endpoint,
    this.bearerToken,
    HttpClient? httpClient,
  })  : endpoint = _validatedEndpoint(endpoint),
        _http = httpClient ?? HttpClient();

  static const int maxBatchSize = 32;
  static const int maxCharactersPerText = 24000;

  final Uri endpoint;
  final String? bearerToken;
  final HttpClient _http;

  static Uri _validatedEndpoint(Uri endpoint) {
    if (endpoint.scheme.toLowerCase() != 'https' ||
        endpoint.host.trim().isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote embedding endpoints must be credential-free HTTPS URLs.',
      );
    }
    return endpoint;
  }

  Future<AiEmbeddingBatch> embed(List<String> texts) async {
    final normalized = texts
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .map(
          (text) => text.length <= maxCharactersPerText
              ? text
              : text.substring(0, maxCharactersPerText),
        )
        .toList(growable: false);
    if (normalized.isEmpty) {
      throw ArgumentError('At least one non-empty text is required.');
    }
    if (normalized.length > maxBatchSize) {
      throw ArgumentError('Embedding batch exceeds $maxBatchSize texts.');
    }

    final request = await _http.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(jsonEncode({'texts': normalized}));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw StateError('Entre na sua conta LexPDF para usar a busca semântica.');
      }
      if (response.statusCode == 429) {
        throw StateError(
          'Limite temporário de indexação semântica atingido. Tente novamente em instantes.',
        );
      }
      throw HttpException('${response.statusCode}: $body', uri: endpoint);
    }

    final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
    final rawVectors = (decoded['vectors'] as List?) ?? const [];
    final vectors = rawVectors.map((raw) {
      final values = raw as List;
      return values.map((value) => (value as num).toDouble()).toList();
    }).toList(growable: false);
    if (vectors.length != normalized.length || vectors.any((v) => v.isEmpty)) {
      throw StateError('O serviço de embeddings retornou um lote inválido.');
    }

    final quota = decoded['quota'] is Map
        ? (decoded['quota'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return AiEmbeddingBatch(
      vectors: vectors,
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
