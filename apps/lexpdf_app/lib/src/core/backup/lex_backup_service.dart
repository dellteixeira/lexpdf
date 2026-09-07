import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../storage/local_database.dart';

class LexBackupValidation {
  const LexBackupValidation({
    required this.valid,
    required this.format,
    required this.version,
    required this.tableCount,
    required this.fileCount,
    this.error,
  });

  final bool valid;
  final String format;
  final int version;
  final int tableCount;
  final int fileCount;
  final String? error;
}

class LexNoteValidation {
  const LexNoteValidation({
    required this.valid,
    required this.version,
    required this.pageCount,
    required this.strokeCount,
    required this.objectCount,
    required this.layerCount,
    this.title,
    this.error,
  });

  final bool valid;
  final int version;
  final int pageCount;
  final int strokeCount;
  final int objectCount;
  final int layerCount;
  final String? title;
  final String? error;
}

class LexNoteImportResult {
  const LexNoteImportResult({
    required this.notebookId,
    required this.title,
    required this.pageCount,
    required this.strokeCount,
    required this.objectCount,
  });

  final String notebookId;
  final String title;
  final int pageCount;
  final int strokeCount;
  final int objectCount;
}

class LexBackupService {
  const LexBackupService(this.db);

  final LocalDatabase db;
  static const int formatVersion = 1;
  static const int lexNoteVersion = 2;

  Future<Uint8List> createBackup() async {
    final snapshot = _snapshotDatabase();
    final databaseBytes = utf8.encode(jsonEncode(snapshot));
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('database.json', databaseBytes));

    final fileEntries = <Map<String, dynamic>>[];
    final documents = db.database.select(
      'SELECT id, local_path FROM documents WHERE local_path IS NOT NULL;',
    );
    for (final row in documents) {
      final path = row['local_path'] as String?;
      if (path == null) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final archivePath = 'documents/${_safeName(row['id'].toString())}.pdf';
      archive.addFile(ArchiveFile.bytes(archivePath, bytes));
      fileEntries.add({
        'documentId': row['id'].toString(),
        'archivePath': archivePath,
        'checksum': sha256.convert(bytes).toString(),
        'size': bytes.length,
      });
    }

    final manifest = <String, dynamic>{
      'format': 'lexbackup',
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'schemaVersion': LocalDatabase.schemaVersion,
      'databaseChecksum': sha256.convert(databaseBytes).toString(),
      'tables': (snapshot['tables'] as Map).keys.toList(),
      'files': fileEntries,
    };
    archive.addFile(
      ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  Future<LexBackupValidation> validate(List<int> bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final manifestFile = archive.findFile('manifest.json');
      final databaseFile = archive.findFile('database.json');
      if (manifestFile == null || databaseFile == null) {
        return _invalidBackup('Manifest or database snapshot is missing.');
      }

      final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
      final version = (manifest['version'] as num?)?.toInt() ?? 0;
      if (manifest['format'] != 'lexbackup' || version != formatVersion) {
        return LexBackupValidation(
          valid: false,
          format: manifest['format']?.toString() ?? 'unknown',
          version: version,
          tableCount: 0,
          fileCount: 0,
          error: 'Unsupported backup format/version.',
        );
      }

      final dbBytes = databaseFile.content;
      if (manifest['databaseChecksum']?.toString() != sha256.convert(dbBytes).toString()) {
        return _invalidBackup('Database snapshot checksum mismatch.', format: 'lexbackup', version: version);
      }

      final snapshot = jsonDecode(utf8.decode(dbBytes)) as Map<String, dynamic>;
      final schemaVersion = (snapshot['schemaVersion'] as num?)?.toInt() ?? 0;
      if (schemaVersion < 1 || schemaVersion > LocalDatabase.schemaVersion) {
        return _invalidBackup(
          'Backup database schema $schemaVersion is not supported by this LexPDF build.',
          format: 'lexbackup',
          version: version,
        );
      }
      final rawTables = snapshot['tables'];
      if (rawTables is! Map) {
        return _invalidBackup('Database tables payload is invalid.', format: 'lexbackup', version: version);
      }
      final tables = rawTables.cast<String, dynamic>();
      for (final entry in tables.entries) {
        if (entry.value is! List) {
          return _invalidBackup('Table ${entry.key} has an invalid row payload.', format: 'lexbackup', version: version);
        }
      }

      final files = (manifest['files'] as List?) ?? const [];
      final seenPaths = <String>{};
      for (final item in files) {
        if (item is! Map) {
          return _invalidBackup('Backup file manifest is invalid.', format: 'lexbackup', version: version);
        }
        final entry = item.cast<String, dynamic>();
        final archivePath = entry['archivePath']?.toString() ?? '';
        if (!_isSafeArchivePath(archivePath) || !seenPaths.add(archivePath)) {
          return _invalidBackup('Unsafe or duplicate bundled document path.', format: 'lexbackup', version: version);
        }
        final file = archive.findFile(archivePath);
        final expectedSize = (entry['size'] as num?)?.toInt();
        if (file == null ||
            expectedSize == null ||
            file.content.length != expectedSize ||
            sha256.convert(file.content).toString() != entry['checksum']?.toString()) {
          return _invalidBackup('A bundled document is missing or corrupted.', format: 'lexbackup', version: version);
        }
      }

      return LexBackupValidation(
        valid: true,
        format: 'lexbackup',
        version: version,
        tableCount: tables.length,
        fileCount: files.length,
      );
    } catch (error) {
      return _invalidBackup(error.toString());
    }
  }

  Future<void> restore(
    List<int> bytes, {
    required Directory documentDirectory,
  }) async {
    final validation = await validate(bytes);
    if (!validation.valid) throw FormatException(validation.error ?? 'Invalid backup.');

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final manifest = jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content)) as Map<String, dynamic>;
    final snapshot = jsonDecode(utf8.decode(archive.findFile('database.json')!.content)) as Map<String, dynamic>;
    final tables = (snapshot['tables'] as Map).cast<String, dynamic>();

    await documentDirectory.create(recursive: true);
    final restoredPaths = <String, String>{};
    final createdFiles = <File>[];
    try {
      for (final raw in (manifest['files'] as List? ?? const [])) {
        final item = (raw as Map).cast<String, dynamic>();
        final documentId = item['documentId'].toString();
        final archived = archive.findFile(item['archivePath'].toString())!;
        final checksum = item['checksum'].toString();
        final target = File(
          '${documentDirectory.path}${Platform.pathSeparator}${_safeName(documentId)}-${checksum.substring(0, 12)}.pdf',
        );
        await target.writeAsBytes(archived.content, flush: true);
        createdFiles.add(target);
        restoredPaths[documentId] = target.path;
      }

      db.database.execute('PRAGMA foreign_keys = OFF;');
      db.database.execute('BEGIN IMMEDIATE;');
      try {
        final existingTables = db.database
            .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%';")
            .map((row) => row['name'] as String)
            .toSet();
        for (final table in tables.keys) {
          if (existingTables.contains(table)) {
            db.database.execute('DELETE FROM ${_quote(table)};');
          }
        }
        for (final entry in tables.entries) {
          final table = entry.key;
          if (!existingTables.contains(table)) continue;
          final rows = entry.value as List<dynamic>;
          for (final rawRow in rows) {
            final row = (rawRow as Map).cast<String, dynamic>();
            if (table == 'documents') {
              final id = row['id']?.toString();
              if (id != null && restoredPaths.containsKey(id)) {
                row['local_path'] = restoredPaths[id];
                row['is_available_offline'] = 1;
              }
            }
            _insertRow(table, row);
          }
        }
        final violations = db.database.select('PRAGMA foreign_key_check;');
        if (violations.isNotEmpty) {
          throw StateError('Backup violates ${violations.length} foreign-key constraints.');
        }
        db.database.execute('COMMIT;');
      } catch (_) {
        db.database.execute('ROLLBACK;');
        rethrow;
      } finally {
        db.database.execute('PRAGMA foreign_keys = ON;');
      }
    } catch (_) {
      for (final file in createdFiles.reversed) {
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  Uint8List exportNotebook(String notebookId) {
    final notebookRows = db.database.select('SELECT * FROM notebooks WHERE id = ?;', [notebookId]);
    if (notebookRows.isEmpty) throw StateError('Notebook not found.');
    final pages = db.database.select(
      'SELECT * FROM notebook_pages WHERE notebook_id = ? ORDER BY page_number;',
      [notebookId],
    );
    final pageIds = pages.map((row) => row['id'].toString()).toList(growable: false);
    final strokes = <Map<String, dynamic>>[];
    final objects = <Map<String, dynamic>>[];
    final layers = <Map<String, dynamic>>[];
    final layerItems = <Map<String, dynamic>>[];
    final hasObjects = _tableExists('notebook_objects');
    final hasLayers = _tableExists('notebook_layers');
    final hasLayerItems = _tableExists('notebook_layer_items');

    for (final pageId in pageIds) {
      strokes.addAll(db.database.select('SELECT * FROM ink_strokes WHERE page_id = ?;', [pageId]).map(_rowToJson));
      if (hasObjects) {
        objects.addAll(db.database.select('SELECT * FROM notebook_objects WHERE page_id = ?;', [pageId]).map(_rowToJson));
      }
      if (hasLayers) {
        final pageLayers = db.database.select('SELECT * FROM notebook_layers WHERE page_id = ? ORDER BY sort_order;', [pageId]);
        layers.addAll(pageLayers.map(_rowToJson));
        if (hasLayerItems) {
          for (final layer in pageLayers) {
            layerItems.addAll(
              db.database.select('SELECT * FROM notebook_layer_items WHERE layer_id = ?;', [layer['id']]).map(_rowToJson),
            );
          }
        }
      }
    }

    final payload = <String, dynamic>{
      'format': 'lexnote',
      'version': lexNoteVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'notebook': _rowToJson(notebookRows.first),
      'pages': pages.map(_rowToJson).toList(growable: false),
      'strokes': strokes,
      'objects': objects,
      'layers': layers,
      'layerItems': layerItems,
    };
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final envelope = <String, dynamic>{
      'format': 'lexnote',
      'version': lexNoteVersion,
      'checksum': sha256.convert(payloadBytes).toString(),
      'payload': base64Encode(payloadBytes),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  LexNoteValidation validateNotebook(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return _invalidNote('Invalid .lexnote root payload.');
      final root = decoded.cast<String, dynamic>();
      final payload = _decodeLexNotePayload(root);
      final version = (payload['version'] as num?)?.toInt() ?? 0;
      if (payload['format'] != 'lexnote' || version < 1 || version > lexNoteVersion) {
        return _invalidNote('Unsupported .lexnote format/version.', version: version);
      }
      final notebook = payload['notebook'];
      final pages = payload['pages'];
      final strokes = payload['strokes'];
      final objects = payload['objects'] ?? const [];
      final layers = payload['layers'] ?? const [];
      final layerItems = payload['layerItems'] ?? const [];
      if (notebook is! Map || pages is! List || strokes is! List || objects is! List || layers is! List || layerItems is! List) {
        return _invalidNote('Malformed .lexnote collections.', version: version);
      }
      if ((notebook['id']?.toString() ?? '').isEmpty || (notebook['title']?.toString() ?? '').isEmpty) {
        return _invalidNote('Notebook identity/title is missing.', version: version);
      }
      final pageIds = <String>{};
      for (final raw in pages) {
        if (raw is! Map) return _invalidNote('Malformed notebook page.', version: version);
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty || !pageIds.add(id)) return _invalidNote('Duplicate or empty notebook page id.', version: version);
      }
      for (final raw in strokes) {
        if (raw is! Map || !pageIds.contains(raw['page_id']?.toString())) {
          return _invalidNote('Stroke references an unknown page.', version: version);
        }
      }
      for (final raw in objects) {
        if (raw is! Map || !pageIds.contains(raw['page_id']?.toString())) {
          return _invalidNote('Object references an unknown page.', version: version);
        }
      }
      final layerIds = <String>{};
      for (final raw in layers) {
        if (raw is! Map || !pageIds.contains(raw['page_id']?.toString())) {
          return _invalidNote('Layer references an unknown page.', version: version);
        }
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty || !layerIds.add(id)) return _invalidNote('Duplicate or empty layer id.', version: version);
      }
      for (final raw in layerItems) {
        if (raw is! Map || !layerIds.contains(raw['layer_id']?.toString())) {
          return _invalidNote('Layer item references an unknown layer.', version: version);
        }
      }
      return LexNoteValidation(
        valid: true,
        version: version,
        pageCount: pages.length,
        strokeCount: strokes.length,
        objectCount: objects.length,
        layerCount: layers.length,
        title: notebook['title']?.toString(),
      );
    } catch (error) {
      return _invalidNote(error.toString());
    }
  }

  LexNoteImportResult importNotebook(List<int> bytes) {
    final validation = validateNotebook(bytes);
    if (!validation.valid) throw FormatException(validation.error ?? 'Invalid .lexnote file.');

    final root = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
    final payload = _decodeLexNotePayload(root);
    final notebook = (payload['notebook'] as Map).cast<String, dynamic>();
    final pages = (payload['pages'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final strokes = (payload['strokes'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final objects = ((payload['objects'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final layers = ((payload['layers'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final layerItems = ((payload['layerItems'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

    final importKey = '${DateTime.now().microsecondsSinceEpoch}';
    final notebookId = 'import-$importKey';
    final pageMap = <String, String>{};
    final strokeMap = <String, String>{};
    final objectMap = <String, String>{};
    final layerMap = <String, String>{};
    for (var i = 0; i < pages.length; i++) {
      pageMap[pages[i]['id'].toString()] = '$notebookId-page-${i + 1}';
    }
    for (var i = 0; i < strokes.length; i++) {
      strokeMap[strokes[i]['id'].toString()] = '$notebookId-stroke-${i + 1}';
    }
    for (var i = 0; i < objects.length; i++) {
      objectMap[objects[i]['id'].toString()] = '$notebookId-object-${i + 1}';
    }
    for (var i = 0; i < layers.length; i++) {
      layerMap[layers[i]['id'].toString()] = '$notebookId-layer-${i + 1}';
    }

    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      final importedNotebook = Map<String, dynamic>.from(notebook)
        ..['id'] = notebookId
        ..['title'] = _uniqueNotebookTitle(notebook['title'].toString())
        ..['created_at'] = now
        ..['updated_at'] = now;
      _insertRow('notebooks', importedNotebook);

      for (final page in pages) {
        final originalId = page['id'].toString();
        final row = Map<String, dynamic>.from(page)
          ..['id'] = pageMap[originalId]
          ..['notebook_id'] = notebookId
          ..['created_at'] = now
          ..['updated_at'] = now;
        _insertRow('notebook_pages', row);
      }
      for (final stroke in strokes) {
        final row = Map<String, dynamic>.from(stroke)
          ..['id'] = strokeMap[stroke['id'].toString()]
          ..['page_id'] = pageMap[stroke['page_id'].toString()]
          ..['created_at'] = now;
        _insertRow('ink_strokes', row);
      }
      if (_tableExists('notebook_objects')) {
        for (final object in objects) {
          final row = Map<String, dynamic>.from(object)
            ..['id'] = objectMap[object['id'].toString()]
            ..['page_id'] = pageMap[object['page_id'].toString()]
            ..['created_at'] = now
            ..['updated_at'] = now;
          _insertRow('notebook_objects', row);
        }
      }

      if (_tableExists('notebook_layers')) {
        if (layers.isEmpty) {
          for (var i = 0; i < pages.length; i++) {
            final pageId = pageMap[pages[i]['id'].toString()]!;
            _insertRow('notebook_layers', {
              'id': '$pageId-layer-1',
              'page_id': pageId,
              'name': 'Camada 1',
              'sort_order': 0,
              'is_visible': 1,
              'is_locked': 0,
              'created_at': now,
              'updated_at': now,
            });
          }
        } else {
          for (final layer in layers) {
            final row = Map<String, dynamic>.from(layer)
              ..['id'] = layerMap[layer['id'].toString()]
              ..['page_id'] = pageMap[layer['page_id'].toString()]
              ..['created_at'] = now
              ..['updated_at'] = now;
            _insertRow('notebook_layers', row);
          }
          if (_tableExists('notebook_layer_items')) {
            for (final item in layerItems) {
              final itemType = item['item_type'].toString();
              final originalItemId = item['item_id'].toString();
              final mappedItemId = itemType == 'stroke' ? strokeMap[originalItemId] : objectMap[originalItemId];
              if (mappedItemId == null) continue;
              _insertRow('notebook_layer_items', {
                ...item,
                'layer_id': layerMap[item['layer_id'].toString()],
                'item_id': mappedItemId,
                'created_at': now,
              });
            }
          }
        }
      }

      final violations = db.database.select('PRAGMA foreign_key_check;');
      if (violations.isNotEmpty) {
        throw StateError('Imported notebook violates ${violations.length} foreign-key constraints.');
      }
      db.database.execute('COMMIT;');
      return LexNoteImportResult(
        notebookId: notebookId,
        title: importedNotebook['title'].toString(),
        pageCount: pages.length,
        strokeCount: strokes.length,
        objectCount: objects.length,
      );
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic> _snapshotDatabase() {
    final tables = <String, dynamic>{};
    final names = db.database.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%' ORDER BY name;",
    );
    for (final row in names) {
      final name = row['name'] as String;
      tables[name] = db.database.select('SELECT * FROM ${_quote(name)};').map(_rowToJson).toList(growable: false);
    }
    return {'schemaVersion': LocalDatabase.schemaVersion, 'tables': tables};
  }

  Map<String, dynamic> _decodeLexNotePayload(Map<String, dynamic> root) {
    if (root['payload'] == null) return root;
    if (root['format'] != 'lexnote' || root['version'] != lexNoteVersion) {
      throw const FormatException('Unsupported .lexnote envelope.');
    }
    final encoded = root['payload'];
    final checksum = root['checksum']?.toString();
    if (encoded is! String || checksum == null) throw const FormatException('Malformed .lexnote envelope.');
    final payloadBytes = base64Decode(encoded);
    if (sha256.convert(payloadBytes).toString() != checksum) {
      throw const FormatException('.lexnote checksum mismatch.');
    }
    final decoded = jsonDecode(utf8.decode(payloadBytes));
    if (decoded is! Map) throw const FormatException('Malformed .lexnote payload.');
    return decoded.cast<String, dynamic>();
  }

  void _insertRow(String table, Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final columns = row.keys.toList(growable: false);
    final values = [for (final column in columns) _fromJsonValue(row[column])];
    final sql = 'INSERT INTO ${_quote(table)} (${columns.map(_quote).join(', ')}) VALUES (${List.filled(columns.length, '?').join(', ')});';
    db.database.execute(sql, values);
  }

  String _uniqueNotebookTitle(String base) {
    final existing = db.database.select('SELECT title FROM notebooks;').map((row) => row['title'].toString()).toSet();
    if (!existing.contains(base)) return base;
    var counter = 2;
    while (existing.contains('$base ($counter)')) {
      counter++;
    }
    return '$base ($counter)';
  }

  bool _tableExists(String name) => db.database
      .select("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1;", [name])
      .isNotEmpty;

  static dynamic _fromJsonValue(dynamic value) {
    if (value is Map && value.length == 1 && value['\$blob'] is String) {
      return Uint8List.fromList(base64Decode(value['\$blob'] as String));
    }
    return value;
  }

  static Map<String, dynamic> _rowToJson(dynamic row) {
    final result = <String, dynamic>{};
    for (final column in row.keys) {
      final value = row[column];
      result[column.toString()] = value is Uint8List ? {'\$blob': base64Encode(value)} : value;
    }
    return result;
  }

  static bool _isSafeArchivePath(String path) {
    if (!path.startsWith('documents/') || path.contains('..') || path.contains('\\') || path.startsWith('/')) return false;
    final segments = path.split('/');
    return segments.length == 2 && segments.last.isNotEmpty;
  }

  static LexBackupValidation _invalidBackup(String error, {String format = 'unknown', int version = 0}) => LexBackupValidation(
        valid: false,
        format: format,
        version: version,
        tableCount: 0,
        fileCount: 0,
        error: error,
      );

  static LexNoteValidation _invalidNote(String error, {int version = 0}) => LexNoteValidation(
        valid: false,
        version: version,
        pageCount: 0,
        strokeCount: 0,
        objectCount: 0,
        layerCount: 0,
        error: error,
      );

  static String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
  static String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}
