import 'dart:convert';
import 'dart:io';

import '../documents/document_provider.dart';
import 'cloud_credential_store.dart';

abstract class DirectCloudDocumentProvider implements SyncDocumentProvider {
  DirectCloudDocumentProvider({
    required this.accountId,
    required this.cacheDirectory,
    CloudCredentialStore credentials = const CloudCredentialStore(),
    HttpClient? httpClient,
  })  : _credentials = credentials,
        _http = httpClient ?? HttpClient();

  final String accountId;
  final Directory cacheDirectory;
  final CloudCredentialStore _credentials;
  final HttpClient _http;

  String get credentialProviderName;

  Future<String> _token() async {
    final value = await _credentials.readToken(
      provider: credentialProviderName,
      accountId: accountId,
    );
    if (value == null || value.isEmpty) {
      throw StateError('$credentialProviderName/$accountId is not authenticated.');
    }
    return value;
  }

  Future<void> _authorize(HttpClientRequest request) async {
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${await _token()}',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  }

  Future<dynamic> jsonRequest(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    headers?.forEach(request.headers.set);
    if (body != null) {
      if (body is List<int>) {
        request.add(body);
      } else if (body is String) {
        request.write(body);
      } else {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
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

  Future<Map<String, dynamic>> streamFileRequest(
    String method,
    Uri uri,
    File file, {
    required String contentType,
    List<int> prefix = const <int>[],
    List<int> suffix = const <int>[],
  }) async {
    final request = await _http.openUrl(method, uri);
    await _authorize(request);
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.contentLength = prefix.length + await file.length() + suffix.length;
    if (prefix.isNotEmpty) request.add(prefix);
    await request.addStream(file.openRead());
    if (suffix.isNotEmpty) request.add(suffix);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, part) => all..addAll(part),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
    }
    if (bytes.isEmpty) return const <String, dynamic>{};
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  Future<String> streamToCache(DocumentRef document, Uri uri) async {
    await cacheDirectory.create(recursive: true);
    final destination = File(
      '${cacheDirectory.path}${Platform.pathSeparator}${document.id}-${_safeName(document.name)}',
    );
    final temp = File('${destination.path}.part');
    final request = await _http.getUrl(uri);
    await _authorize(request);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bytes = await response.fold<List<int>>(
        <int>[],
        (all, part) => all..addAll(part),
      );
      throw HttpException('${response.statusCode}: ${utf8.decode(bytes)}', uri: uri);
    }
    if (await temp.exists()) await temp.delete();
    final sink = temp.openWrite();
    try {
      await response.pipe(sink);
      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);
      return destination.path;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  static String safePathSegment(String value) => Uri.encodeComponent(value);
  static String basename(String path) => path.replaceAll('\\', '/').split('/').last;
  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

class GoogleDriveDocumentProvider extends DirectCloudDocumentProvider {
  GoogleDriveDocumentProvider({
    required super.accountId,
    required super.cacheDirectory,
    super.credentials,
    super.httpClient,
  });

  @override
  DocumentProviderKind get kind => DocumentProviderKind.googleDrive;

  @override
  String get credentialProviderName => 'google_drive';

  static const _base = 'https://www.googleapis.com/drive/v3';
  static const _uploadBase = 'https://www.googleapis.com/upload/drive/v3';
  static const _fields = 'id,name,parents,modifiedTime,md5Checksum,size';

  @override
  Future<List<DocumentRef>> list({String? parentId}) async {
    final parent = parentId ?? 'root';
    final query =
        "'$parent' in parents and trashed=false and mimeType='application/pdf'";
    String? pageToken;
    final results = <DocumentRef>[];
    do {
      final uri = Uri.parse('$_base/files').replace(queryParameters: {
        'q': query,
        'fields': 'nextPageToken,files($_fields)',
        'pageSize': '1000',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final data =
          (await jsonRequest('GET', uri) as Map).cast<String, dynamic>();
      for (final raw in (data['files'] as List? ?? const [])) {
        results.add(_ref((raw as Map).cast<String, dynamic>()));
      }
      pageToken = data['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);
    return results;
  }

  @override
  Future<DocumentRef?> getById(String id) async {
    try {
      final uri = Uri.parse(
        '$_base/files/${DirectCloudDocumentProvider.safePathSegment(id)}',
      ).replace(queryParameters: {'fields': _fields});
      return _ref(
        (await jsonRequest('GET', uri) as Map).cast<String, dynamic>(),
      );
    } on HttpException catch (error) {
      if (error.message.startsWith('404:')) return null;
      rethrow;
    }
  }

  @override
  Future<String> ensureLocalCopy(DocumentRef document) async {
    final existing = document.localPath;
    if (existing != null && await File(existing).exists()) return existing;
    final id = document.remoteId ?? document.id;
    final uri = Uri.parse(
      '$_base/files/${DirectCloudDocumentProvider.safePathSegment(id)}',
    ).replace(queryParameters: {'alt': 'media'});
    return streamToCache(document, uri);
  }

  @override
  Future<DocumentRef> upload(String localPath, {String? parentId}) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', localPath);
    }
    final boundary = 'lexpdf-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': DirectCloudDocumentProvider.basename(localPath),
      'mimeType': 'application/pdf',
      if (parentId != null) 'parents': [parentId],
    });
    final prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Type: application/pdf\r\n\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    final uri = Uri.parse('$_uploadBase/files').replace(queryParameters: {
      'uploadType': 'multipart',
      'fields': _fields,
    });
    final data = await streamFileRequest(
      'POST',
      uri,
      file,
      contentType: 'multipart/related; boundary=$boundary',
      prefix: prefix,
      suffix: suffix,
    );
    return _ref(data, localPath: localPath);
  }

  @override
  Future<DocumentRef> replaceContent(
    DocumentRef document,
    String localPath,
  ) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', localPath);
    }
    final id = document.remoteId ?? document.id;
    final uri = Uri.parse(
      '$_uploadBase/files/${DirectCloudDocumentProvider.safePathSegment(id)}',
    ).replace(queryParameters: {'uploadType': 'media', 'fields': _fields});
    final data = await streamFileRequest(
      'PATCH',
      uri,
      file,
      contentType: 'application/pdf',
    );
    return _ref(data, localPath: localPath);
  }

  @override
  Future<void> rename(DocumentRef document, String newName) async {
    final id = document.remoteId ?? document.id;
    await jsonRequest(
      'PATCH',
      Uri.parse(
        '$_base/files/${DirectCloudDocumentProvider.safePathSegment(id)}',
      ),
      body: {'name': newName},
    );
  }

  @override
  Future<void> move(DocumentRef document, {String? parentId}) async {
    if (parentId == null) return;
    final id = document.remoteId ?? document.id;
    final current = await getById(id);
    final oldParent = current?.remotePath;
    final uri = Uri.parse(
      '$_base/files/${DirectCloudDocumentProvider.safePathSegment(id)}',
    ).replace(queryParameters: {
      'addParents': parentId,
      if (oldParent != null && oldParent.isNotEmpty) 'removeParents': oldParent,
    });
    await jsonRequest('PATCH', uri, body: const <String, dynamic>{});
  }

  @override
  Future<void> delete(DocumentRef document) async {
    final id = document.remoteId ?? document.id;
    await jsonRequest(
      'DELETE',
      Uri.parse(
        '$_base/files/${DirectCloudDocumentProvider.safePathSegment(id)}',
      ),
    );
  }

  DocumentRef _ref(Map<String, dynamic> data, {String? localPath}) {
    final parents =
        (data['parents'] as List?)?.map((e) => e.toString()).toList() ??
            const [];
    return DocumentRef(
      id: data['id'].toString(),
      name: data['name']?.toString() ?? 'document.pdf',
      provider: kind,
      localPath: localPath,
      remoteId: data['id'].toString(),
      remotePath: parents.isEmpty ? null : parents.first,
      checksum: data['md5Checksum']?.toString(),
      remoteVersion: data['modifiedTime']?.toString(),
      availableOffline: localPath != null,
      syncState: localPath == null
          ? DocumentSyncState.remoteOnly
          : DocumentSyncState.synced,
    );
  }
}

class OneDriveDocumentProvider extends DirectCloudDocumentProvider {
  OneDriveDocumentProvider({
    required super.accountId,
    required super.cacheDirectory,
    super.credentials,
    super.httpClient,
  });

  @override
  DocumentProviderKind get kind => DocumentProviderKind.oneDrive;

  @override
  String get credentialProviderName => 'onedrive';

  static const _base = 'https://graph.microsoft.com/v1.0/me/drive';

  @override
  Future<List<DocumentRef>> list({String? parentId}) async {
    var uri = parentId == null
        ? Uri.parse('$_base/root/children')
        : Uri.parse(
            '$_base/items/${DirectCloudDocumentProvider.safePathSegment(parentId)}/children',
          );
    final results = <DocumentRef>[];
    while (true) {
      final data =
          (await jsonRequest('GET', uri) as Map).cast<String, dynamic>();
      for (final raw in (data['value'] as List? ?? const [])) {
        final item = (raw as Map).cast<String, dynamic>();
        if (item['file'] == null ||
            item['name']?.toString().toLowerCase().endsWith('.pdf') != true) {
          continue;
        }
        results.add(_ref(item));
      }
      final next = data['@odata.nextLink']?.toString();
      if (next == null || next.isEmpty) break;
      uri = Uri.parse(next);
    }
    return results;
  }

  @override
  Future<DocumentRef?> getById(String id) async {
    try {
      final data = (await jsonRequest(
        'GET',
        Uri.parse(
          '$_base/items/${DirectCloudDocumentProvider.safePathSegment(id)}',
        ),
      ) as Map)
          .cast<String, dynamic>();
      return _ref(data);
    } on HttpException catch (error) {
      if (error.message.startsWith('404:')) return null;
      rethrow;
    }
  }

  @override
  Future<String> ensureLocalCopy(DocumentRef document) async {
    final existing = document.localPath;
    if (existing != null && await File(existing).exists()) return existing;
    final id = document.remoteId ?? document.id;
    return streamToCache(
      document,
      Uri.parse(
        '$_base/items/${DirectCloudDocumentProvider.safePathSegment(id)}/content',
      ),
    );
  }

  @override
  Future<DocumentRef> upload(String localPath, {String? parentId}) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', localPath);
    }
    final name = DirectCloudDocumentProvider.basename(localPath);
    final encodedName = DirectCloudDocumentProvider.safePathSegment(name);
    final uri = parentId == null
        ? Uri.parse('$_base/root:/$encodedName:/content')
        : Uri.parse(
            '$_base/items/${DirectCloudDocumentProvider.safePathSegment(parentId)}:/$encodedName:/content',
          );
    final data = await streamFileRequest(
      'PUT',
      uri,
      file,
      contentType: 'application/pdf',
    );
    return _ref(data, localPath: localPath);
  }

  @override
  Future<DocumentRef> replaceContent(
    DocumentRef document,
    String localPath,
  ) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', localPath);
    }
    final id = document.remoteId ?? document.id;
    final data = await streamFileRequest(
      'PUT',
      Uri.parse(
        '$_base/items/${DirectCloudDocumentProvider.safePathSegment(id)}/content',
      ),
      file,
      contentType: 'application/pdf',
    );
    return _ref(data, localPath: localPath);
  }

  @override
  Future<void> rename(DocumentRef document, String newName) async {
    final id = document.remoteId ?? document.id;
    await jsonRequest(
      'PATCH',
      Uri.parse(
        '$_base/items/${DirectCloudDocumentProvider.safePathSegment(id)}',
      ),
      body: {'name': newName},
    );
  }

  @override
  Future<void> move(DocumentRef document, {String? parentId}) async {
    if (parentId == null) return;
    final id = document.remoteId ?? document.id;
    await jsonRequest(
      'PATCH',
      Uri.parse(
        '$_base/items/${DirectCloudDocumentProvider.safePathSegment(id)}',
      ),
      body: {
        'parentReference': {'id': parentId},
      },
    );
  }

  @override
  Future<void> delete(DocumentRef document) async {
    final id = document.remoteId ?? document.id;
    await jsonRequest(
      'DELETE',
      Uri.parse(
        '$_base/items/${DirectCloudDocumentProvider.safePathSegment(id)}',
      ),
    );
  }

  DocumentRef _ref(Map<String, dynamic> data, {String? localPath}) {
    final file = (data['file'] as Map?)?.cast<String, dynamic>();
    final hashes = (file?['hashes'] as Map?)?.cast<String, dynamic>();
    return DocumentRef(
      id: data['id'].toString(),
      name: data['name']?.toString() ?? 'document.pdf',
      provider: kind,
      localPath: localPath,
      remoteId: data['id'].toString(),
      remotePath: (data['parentReference'] as Map?)?['id']?.toString(),
      checksum:
          hashes?['sha1Hash']?.toString() ?? hashes?['quickXorHash']?.toString(),
      remoteVersion:
          data['eTag']?.toString() ?? data['lastModifiedDateTime']?.toString(),
      availableOffline: localPath != null,
      syncState: localPath == null
          ? DocumentSyncState.remoteOnly
          : DocumentSyncState.synced,
    );
  }
}
