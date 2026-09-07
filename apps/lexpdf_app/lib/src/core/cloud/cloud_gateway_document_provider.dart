import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final uri = _uri('/v1/cloud/$_providerName/files', {
      'account': accountId,
      if (parentId != null) 'parent': parentId,
    });
    final data = await _json('GET', uri) as List<dynamic>;
    return data.map((value) => _fromJson((value as Map).cast<String, dynamic>())).toList(growable: false);
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
    final file = File('${cacheDirectory.path}${Platform.pathSeparator}${document.id}-${_safeName(document.name)}');
    final uri = _uri('/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}/content', {'account': accountId});
    await file.writeAsBytes(await _bytes('GET', uri), flush: true);
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
    final decoded = jsonDecode(utf8.decode(await _bytesRequest('POST', uri, await file.readAsBytes()))) as Map<String, dynamic>;
    return _fromJson(decoded).copyWith(localPath: localPath, availableOffline: true, syncState: DocumentSyncState.synced);
  }

  @override
  Future<DocumentRef> replaceContent(DocumentRef document, String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) throw FileSystemException('File not found', localPath);
    final uri = _uri('/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}/content', {'account': accountId});
    final decoded = jsonDecode(utf8.decode(await _bytesRequest('PUT', uri, await file.readAsBytes()))) as Map<String, dynamic>;
    return _fromJson(decoded).copyWith(localPath: localPath, availableOffline: true, syncState: DocumentSyncState.synced);
  }

  @override
  Future<void> rename(DocumentRef document, String newName) async {
    await _json('PATCH', _uri('/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}', {'account': accountId}), body: {'name': newName});
  }

  @override
  Future<void> move(DocumentRef document, {String? parentId}) async {
    await _json('PATCH', _uri('/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}', {'account': accountId}), body: {'parentId': parentId});
  }

  @override
  Future<void> delete(DocumentRef document) async {
    await _json('DELETE', _uri('/v1/cloud/$_providerName/files/${document.remoteId ?? document.id}', {'account': accountId}));
  }

  Uri _uri(String path, Map<String, String> query) => gatewayBaseUrl.replace(
        path: '${gatewayBaseUrl.path.endsWith('/') ? gatewayBaseUrl.path.substring(0, gatewayBaseUrl.path.length - 1) : gatewayBaseUrl.path}$path',
        queryParameters: query,
      );

  Future<void> _authorize(HttpClientRequest request) async {
    final token = await _credentials.readToken(provider: _providerName, accountId: accountId);
    if (token == null || token.isEmpty) throw StateError('Cloud account $_providerName/$accountId is not authenticated.');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  }

  Future<dynamic> _json(String method, Uri uri, {Map<String, dynamic>? body}) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (all, part) => all..addAll(part));
    if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
    if (bytes.isEmpty) return null;
    return jsonDecode(utf8.decode(bytes));
  }

  Future<Uint8List> _bytes(String method, Uri uri) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (all, part) => all..addAll(part));
    if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _bytesRequest(String method, Uri uri, Uint8List body) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    request.headers.contentType = ContentType.binary;
    request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (all, part) => all..addAll(part));
    if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
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

  String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
