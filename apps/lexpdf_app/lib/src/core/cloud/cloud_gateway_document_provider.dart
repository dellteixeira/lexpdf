import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../documents/document_provider.dart';
import 'cloud_credential_store.dart';

class CloudGatewayDocumentProvider implements SyncDocumentProvider {
  CloudGatewayDocumentProvider({
    required this.kind,
    required this.accountId,
    required this.gatewayBaseUrl,
    required this.cacheDirectory,
    CloudCredentialStore credentials = const CloudCredentialStore(),
    HttpClient? httpClient,
  })  : _credentials = credentials,
        _http = httpClient ?? HttpClient();

  @override
  final DocumentProviderKind kind;
  final String accountId;
  final Uri gatewayBaseUrl;
  final Directory cacheDirectory;
  final CloudCredentialStore _credentials;
  final HttpClient _http;

  String get _providerName => switch (kind) {
        DocumentProviderKind.googleDrive => 'google_drive',
        DocumentProviderKind.oneDrive => 'onedrive',
        DocumentProviderKind.iCloud => 'icloud',
        DocumentProviderKind.r2 => 'r2',
        DocumentProviderKind.local => 'local',
      };

  @override
  Future<List<DocumentRef>> list({String? parentId}) async {
    final results = <DocumentRef>[];
    String? cursor;
    do {
      final uri = _uri('/v1/cloud/$_providerName/files', {
        'account': accountId,
        if (parentId != null) 'parent': parentId,
        if (cursor != null) 'cursor': cursor,
        'limit': '500',
      });
      final data = await _json('GET', uri);
      if (data is List<dynamic>) {
        results.addAll(
          data.map((value) => _fromJson((value as Map).cast<String, dynamic>())),
        );
        break;
      }
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Resposta inválida da listagem em nuvem.');
      }
      final values = data['items'] as List<dynamic>? ?? const <dynamic>[];
      results.addAll(
        values.map((value) => _fromJson((value as Map).cast<String, dynamic>())),
      );
      final truncated = data['truncated'] == true;
      final next = data['cursor']?.toString();
      cursor = truncated && next != null && next.isNotEmpty ? next : null;
    } while (cursor != null);
    return results;
  }

  @override
  Future<DocumentRef?> getById(String id) async {
    final uri = _uri('/v1/cloud/$_providerName/files/$id', {'account': accountId});
    try {
      return _fromJson(await _json('GET', uri) as Map<String, dynamic>);
    } on HttpException catch (error) {
      if (error.message.contains('404')) return null;
      rethrow;
    }
  }

  @override
  Future<String> ensureLocalCopy(DocumentRef document) async {
    final existing = document.localPath;
    if (existing != null && await File(existing).exists()) return existing;
    await cacheDirectory.create(recursive: true);
    final file = File(
      '${cacheDirectory.path}${Platform.pathSeparator}${document.id}-${_safeName(document.name)}',
    );
    final uri = _uri(
      '/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}/content',
      {'account': accountId},
    );
    await _downloadToFile(uri, file);
    return file.path;
  }

  @override
  Future<DocumentRef> upload(String localPath, {String? parentId}) async {
    final file = File(localPath);
    if (!await file.exists()) throw FileSystemException('File not found', localPath);
    final uri = _uri('/v1/cloud/$_providerName/files', {
      'account': accountId,
      if (parentId != null) 'parent': parentId,
      'name': _basename(localPath),
    });
    final decoded = jsonDecode(
      utf8.decode(await _fileRequest('POST', uri, file)),
    ) as Map<String, dynamic>;
    return _fromJson(decoded).copyWith(
      localPath: localPath,
      availableOffline: true,
      syncState: DocumentSyncState.synced,
    );
  }

  @override
  Future<DocumentRef> replaceContent(DocumentRef document, String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) throw FileSystemException('File not found', localPath);
    final uri = _uri(
      '/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}/content',
      {'account': accountId},
    );
    final decoded = jsonDecode(
      utf8.decode(
        await _fileRequest(
          'PUT',
          uri,
          file,
          ifMatch: document.remoteVersion,
        ),
      ),
    ) as Map<String, dynamic>;
    return _fromJson(decoded).copyWith(
      localPath: localPath,
      availableOffline: true,
      syncState: DocumentSyncState.synced,
    );
  }

  @override
  Future<void> rename(DocumentRef document, String newName) async {
    await _json(
      'PATCH',
      _uri(
        '/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}',
        {'account': accountId},
      ),
      body: {'name': newName},
    );
  }

  @override
  Future<void> move(DocumentRef document, {String? parentId}) async {
    await _json(
      'PATCH',
      _uri(
        '/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}',
        {'account': accountId},
      ),
      body: {'parentId': parentId},
    );
  }

  @override
  Future<void> delete(DocumentRef document) async {
    await _json(
      'DELETE',
      _uri(
        '/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}',
        {'account': accountId},
      ),
    );
  }

  Uri _uri(String path, Map<String, String> query) => gatewayBaseUrl.replace(
        path:
            '${gatewayBaseUrl.path.endsWith('/') ? gatewayBaseUrl.path.substring(0, gatewayBaseUrl.path.length - 1) : gatewayBaseUrl.path}$path',
        queryParameters: query,
      );

  Future<void> _authorize(HttpClientRequest request) async {
    var token = await _credentials.readToken(
      provider: _providerName,
      accountId: accountId,
    );
    if ((token == null || token.isEmpty) && kind == DocumentProviderKind.r2) {
      token = Supabase.instance.client.auth.currentSession?.accessToken;
    }
    if (token == null || token.isEmpty) {
      throw StateError(
        'Cloud account $_providerName/$accountId is not authenticated.',
      );
    }
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  }

  Future<dynamic> _json(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, part) => all..addAll(part),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
    }
    if (bytes.isEmpty) return null;
    return jsonDecode(utf8.decode(bytes));
  }

  Future<void> _downloadToFile(Uri uri, File destination) async {
    final request = await _http.getUrl(uri);
    await _authorize(request);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBytes = await response.fold<List<int>>(
        <int>[],
        (all, part) => all..addAll(part),
      );
      throw HttpException(
        '${response.statusCode}: ${utf8.decode(errorBytes)}',
        uri: uri,
      );
    }
    final temp = File('${destination.path}.part');
    final sink = temp.openWrite();
    try {
      await response.pipe(sink);
      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);
    } catch (_) {
      await sink.close();
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<Uint8List> _fileRequest(
    String method,
    Uri uri,
    File file, {
    String? ifMatch,
  }) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    request.headers.contentType = ContentType('application', 'pdf');
    request.contentLength = await file.length();
    if (ifMatch != null && ifMatch.isNotEmpty) {
      request.headers.set(HttpHeaders.ifMatchHeader, ifMatch);
    }
    await request.addStream(file.openRead());
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, part) => all..addAll(part),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
    }
    return Uint8List.fromList(bytes);
  }

  DocumentRef _fromJson(Map<String, dynamic> data) => DocumentRef(
        id: (data['id'] ?? data['remoteId']).toString(),
        name: (data['name'] ?? 'document.pdf').toString(),
        provider: kind,
        remoteId: (data['remoteId'] ?? data['id'])?.toString(),
        remotePath: data['remotePath']?.toString(),
        checksum: data['checksum']?.toString(),
        remoteVersion: (data['version'] ?? data['etag'])?.toString(),
        availableOffline: false,
        syncState: DocumentSyncState.remoteOnly,
      );

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
