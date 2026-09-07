import 'local_database.dart';

enum NotebookLayerItemType { stroke, object }

class NotebookLayer {
  const NotebookLayer({
    required this.id,
    required this.pageId,
    required this.name,
    required this.sortOrder,
    required this.isVisible,
    required this.isLocked,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String pageId;
  final String name;
  final int sortOrder;
  final bool isVisible;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class LocalNotebookLayerStore {
  const LocalNotebookLayerStore(this.db);

  final LocalDatabase db;

  Future<List<NotebookLayer>> listLayers(String pageId) async {
    final rows = db.database.select(
      '''
      SELECT * FROM notebook_layers
      WHERE page_id = ?
      ORDER BY sort_order ASC, created_at ASC;
      ''',
      [pageId],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<NotebookLayer> ensureDefaultLayer(String pageId) async {
    _requirePage(pageId);
    final existing = await listLayers(pageId);
    if (existing.isNotEmpty) return existing.first;

    final now = DateTime.now().toUtc();
    final id = 'layer-${pageId}-${now.microsecondsSinceEpoch.toRadixString(36)}';
    db.database.execute(
      '''
      INSERT INTO notebook_layers(
        id, page_id, name, sort_order, is_visible, is_locked, created_at, updated_at
      ) VALUES (?, ?, ?, 0, 1, 0, ?, ?);
      ''',
      [id, pageId, 'Camada 1', now.toIso8601String(), now.toIso8601String()],
    );
    return (await listLayers(pageId)).first;
  }

  Future<NotebookLayer> createLayer(String pageId, {String? name}) async {
    _requirePage(pageId);
    final layers = await listLayers(pageId);
    final now = DateTime.now().toUtc();
    final normalized = (name ?? '').trim();
    final id = 'layer-${pageId}-${now.microsecondsSinceEpoch.toRadixString(36)}';
    final sortOrder = layers.length;
    final title = normalized.isEmpty ? 'Camada ${sortOrder + 1}' : normalized;
    db.database.execute(
      '''
      INSERT INTO notebook_layers(
        id, page_id, name, sort_order, is_visible, is_locked, created_at, updated_at
      ) VALUES (?, ?, ?, ?, 1, 0, ?, ?);
      ''',
      [id, pageId, title, sortOrder, now.toIso8601String(), now.toIso8601String()],
    );
    return (await listLayers(pageId)).last;
  }

  Future<void> renameLayer(String layerId, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    db.database.execute(
      'UPDATE notebook_layers SET name = ?, updated_at = ? WHERE id = ?;',
      [normalized, DateTime.now().toUtc().toIso8601String(), layerId],
    );
  }

  Future<void> setVisibility(String layerId, bool visible) async {
    db.database.execute(
      'UPDATE notebook_layers SET is_visible = ?, updated_at = ? WHERE id = ?;',
      [visible ? 1 : 0, DateTime.now().toUtc().toIso8601String(), layerId],
    );
  }

  Future<void> setLocked(String layerId, bool locked) async {
    db.database.execute(
      'UPDATE notebook_layers SET is_locked = ?, updated_at = ? WHERE id = ?;',
      [locked ? 1 : 0, DateTime.now().toUtc().toIso8601String(), layerId],
    );
  }

  Future<void> reorderLayers(String pageId, List<String> orderedLayerIds) async {
    final current = await listLayers(pageId);
    final currentIds = current.map((layer) => layer.id).toSet();
    if (orderedLayerIds.length != current.length ||
        orderedLayerIds.toSet().length != orderedLayerIds.length ||
        !orderedLayerIds.every(currentIds.contains)) {
      throw ArgumentError('A ordem deve conter exatamente as camadas da página.');
    }

    db.database.execute('BEGIN IMMEDIATE;');
    try {
      const offset = 1000000;
      for (var index = 0; index < orderedLayerIds.length; index++) {
        db.database.execute(
          'UPDATE notebook_layers SET sort_order = ? WHERE id = ? AND page_id = ?;',
          [offset + index, orderedLayerIds[index], pageId],
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      for (var index = 0; index < orderedLayerIds.length; index++) {
        db.database.execute(
          '''
          UPDATE notebook_layers
          SET sort_order = ?, updated_at = ?
          WHERE id = ? AND page_id = ?;
          ''',
          [index, now, orderedLayerIds[index], pageId],
        );
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> assignStroke(String layerId, String strokeId) async {
    _assign(layerId, NotebookLayerItemType.stroke, strokeId);
  }

  Future<void> assignObject(String layerId, String objectId) async {
    _assign(layerId, NotebookLayerItemType.object, objectId);
  }

  Future<Map<String, String>> itemLayerMap(
    String pageId,
    NotebookLayerItemType type,
  ) async {
    final rows = db.database.select(
      '''
      SELECT i.item_id, i.layer_id
      FROM notebook_layer_items i
      JOIN notebook_layers l ON l.id = i.layer_id
      WHERE l.page_id = ? AND i.item_type = ?;
      ''',
      [pageId, _typeToDb(type)],
    );
    return {
      for (final row in rows)
        row['item_id'] as String: row['layer_id'] as String,
    };
  }

  Future<void> replaceAssignments({
    required String pageId,
    required Map<String, String> strokeLayerIds,
    required Map<String, String> objectLayerIds,
  }) async {
    final layers = await listLayers(pageId);
    if (layers.isEmpty) await ensureDefaultLayer(pageId);
    final validLayers = (await listLayers(pageId)).map((e) => e.id).toSet();
    final fallback = (await listLayers(pageId)).first.id;

    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute(
        '''DELETE FROM notebook_layer_items
           WHERE layer_id IN (SELECT id FROM notebook_layers WHERE page_id = ?);''',
        [pageId],
      );
      final strokeRows = db.database.select(
        'SELECT id FROM ink_strokes WHERE page_id = ?;',
        [pageId],
      );
      for (final row in strokeRows) {
        final itemId = row['id'] as String;
        final requested = strokeLayerIds[itemId];
        final layerId = requested != null && validLayers.contains(requested)
            ? requested
            : fallback;
        _insertAssignment(layerId, NotebookLayerItemType.stroke, itemId);
      }
      final objectRows = db.database.select(
        'SELECT id FROM notebook_objects WHERE page_id = ?;',
        [pageId],
      );
      for (final row in objectRows) {
        final itemId = row['id'] as String;
        final requested = objectLayerIds[itemId];
        final layerId = requested != null && validLayers.contains(requested)
            ? requested
            : fallback;
        _insertAssignment(layerId, NotebookLayerItemType.object, itemId);
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<String?> layerIdForItem(
    NotebookLayerItemType type,
    String itemId,
  ) async {
    final rows = db.database.select(
      '''
      SELECT layer_id FROM notebook_layer_items
      WHERE item_type = ? AND item_id = ? LIMIT 1;
      ''',
      [_typeToDb(type), itemId],
    );
    return rows.isEmpty ? null : rows.first['layer_id'] as String;
  }

  Future<void> deleteLayer(String layerId) async {
    final layerRows = db.database.select(
      'SELECT page_id FROM notebook_layers WHERE id = ? LIMIT 1;',
      [layerId],
    );
    if (layerRows.isEmpty) return;
    final pageId = layerRows.single['page_id'] as String;
    final layers = await listLayers(pageId);
    if (layers.length <= 1) {
      throw StateError('Uma página precisa manter pelo menos uma camada.');
    }
    final fallback = layers.firstWhere((layer) => layer.id != layerId);

    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute(
        'UPDATE notebook_layer_items SET layer_id = ? WHERE layer_id = ?;',
        [fallback.id, layerId],
      );
      db.database.execute('DELETE FROM notebook_layers WHERE id = ?;', [layerId]);
      final remaining = db.database.select(
        '''
        SELECT id FROM notebook_layers
        WHERE page_id = ? ORDER BY sort_order ASC, created_at ASC;
        ''',
        [pageId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      for (var index = 0; index < remaining.length; index++) {
        db.database.execute(
          'UPDATE notebook_layers SET sort_order = ?, updated_at = ? WHERE id = ?;',
          [index, now, remaining[index]['id'] as String],
        );
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _assign(
    String layerId,
    NotebookLayerItemType type,
    String itemId,
  ) {
    final layerRows = db.database.select(
      'SELECT page_id FROM notebook_layers WHERE id = ? LIMIT 1;',
      [layerId],
    );
    if (layerRows.isEmpty) throw StateError('Camada não encontrada: $layerId');
    final pageId = layerRows.single['page_id'] as String;
    final table = switch (type) {
      NotebookLayerItemType.stroke => 'ink_strokes',
      NotebookLayerItemType.object => 'notebook_objects',
    };
    final itemRows = db.database.select(
      'SELECT page_id FROM $table WHERE id = ? LIMIT 1;',
      [itemId],
    );
    if (itemRows.isEmpty) throw StateError('Item não encontrado: $itemId');
    if (itemRows.single['page_id'] as String != pageId) {
      throw ArgumentError('O item e a camada precisam pertencer à mesma página.');
    }
    _insertAssignment(layerId, type, itemId);
  }

  void _insertAssignment(
    String layerId,
    NotebookLayerItemType type,
    String itemId,
  ) {
    db.database.execute(
      '''
      INSERT INTO notebook_layer_items(layer_id, item_type, item_id, created_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(item_type, item_id) DO UPDATE SET layer_id = excluded.layer_id;
      ''',
      [layerId, _typeToDb(type), itemId, DateTime.now().toUtc().toIso8601String()],
    );
  }

  void _requirePage(String pageId) {
    final rows = db.database.select(
      'SELECT id FROM notebook_pages WHERE id = ? LIMIT 1;',
      [pageId],
    );
    if (rows.isEmpty) throw StateError('Página não encontrada: $pageId');
  }

  NotebookLayer _fromRow(dynamic row) => NotebookLayer(
        id: row['id'] as String,
        pageId: row['page_id'] as String,
        name: row['name'] as String,
        sortOrder: row['sort_order'] as int,
        isVisible: (row['is_visible'] as int) == 1,
        isLocked: (row['is_locked'] as int) == 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  static String _typeToDb(NotebookLayerItemType type) => switch (type) {
        NotebookLayerItemType.stroke => 'stroke',
        NotebookLayerItemType.object => 'object',
      };
}
