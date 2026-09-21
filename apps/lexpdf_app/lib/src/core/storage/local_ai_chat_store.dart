import 'dart:convert';

import 'local_database.dart';

enum AiChatScope { library, document }

enum AiChatRole { user, assistant }

class AiChatSource {
  const AiChatSource({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.excerpt,
    this.score,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final String excerpt;
  final double? score;

  Map<String, Object?> toJson() => {
        'documentId': documentId,
        'documentTitle': documentTitle,
        'pageNumber': pageNumber,
        'excerpt': excerpt,
        'score': score,
      };

  factory AiChatSource.fromJson(Map<String, dynamic> json) => AiChatSource(
        documentId: json['documentId']?.toString() ?? '',
        documentTitle: json['documentTitle']?.toString() ?? '',
        pageNumber: int.tryParse(json['pageNumber']?.toString() ?? '') ?? 1,
        excerpt: json['excerpt']?.toString() ?? '',
        score: json['score'] is num
            ? (json['score'] as num).toDouble()
            : double.tryParse(json['score']?.toString() ?? ''),
      );
}

class AiChatSession {
  const AiChatSession({
    required this.id,
    required this.scope,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.documentId,
    this.documentTitle,
  });

  final String id;
  final AiChatScope scope;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? documentId;
  final String? documentTitle;
}

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.sources = const [],
  });

  final String id;
  final String sessionId;
  final AiChatRole role;
  final String content;
  final List<AiChatSource> sources;
  final DateTime createdAt;
}

class LocalAiChatStore {
  LocalAiChatStore(this.db) {
    _ensureTables();
  }

  final LocalDatabase db;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS ai_chat_sessions (
        id TEXT PRIMARY KEY,
        scope TEXT NOT NULL CHECK(scope IN ('library', 'document')),
        document_id TEXT REFERENCES documents(id) ON DELETE CASCADE,
        document_title TEXT,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS ai_chat_sessions_scope_idx
      ON ai_chat_sessions(scope, document_id, updated_at DESC);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS ai_chat_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES ai_chat_sessions(id) ON DELETE CASCADE,
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL,
        sources_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS ai_chat_messages_session_idx
      ON ai_chat_messages(session_id, created_at);
    ''');
  }

  Future<AiChatSession?> latestSession({
    required AiChatScope scope,
    String? documentId,
  }) async {
    final rows = db.database.select('''
      SELECT *
      FROM ai_chat_sessions
      WHERE scope = ?
        AND (
          (? IS NULL AND document_id IS NULL)
          OR document_id = ?
        )
      ORDER BY updated_at DESC
      LIMIT 1;
    ''', [scope.name, documentId, documentId]);
    return rows.isEmpty ? null : _sessionFromRow(rows.first);
  }

  Future<AiChatSession> createSession({
    required AiChatScope scope,
    String? documentId,
    String? documentTitle,
  }) async {
    if (scope == AiChatScope.document &&
        (documentId == null || documentId.trim().isEmpty)) {
      throw ArgumentError('Document chat requires a document id.');
    }
    final now = DateTime.now().toUtc();
    final id = 'ai-chat-${now.microsecondsSinceEpoch.toRadixString(36)}';
    final title = scope == AiChatScope.document
        ? 'Chat — ${documentTitle?.trim().isNotEmpty == true ? documentTitle!.trim() : 'PDF'}'
        : 'Chat da biblioteca';
    db.database.execute('''
      INSERT INTO ai_chat_sessions(
        id, scope, document_id, document_title, title, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
    ''', [
      id,
      scope.name,
      documentId,
      documentTitle,
      title,
      now.toIso8601String(),
      now.toIso8601String(),
    ]);
    return AiChatSession(
      id: id,
      scope: scope,
      documentId: documentId,
      documentTitle: documentTitle,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<List<AiChatMessage>> listMessages(
    String sessionId, {
    int limit = 200,
  }) async {
    final rows = db.database.select('''
      SELECT *
      FROM ai_chat_messages
      WHERE session_id = ?
      ORDER BY created_at ASC
      LIMIT ?;
    ''', [sessionId, limit]);
    return rows.map(_messageFromRow).toList(growable: false);
  }

  Future<AiChatMessage> appendMessage({
    required String sessionId,
    required AiChatRole role,
    required String content,
    List<AiChatSource> sources = const [],
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) throw ArgumentError('Chat message cannot be empty.');
    final now = DateTime.now().toUtc();
    final id =
        'ai-msg-${now.microsecondsSinceEpoch.toRadixString(36)}-${role.name}';
    db.database.execute('''
      INSERT INTO ai_chat_messages(
        id, session_id, role, content, sources_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?);
    ''', [
      id,
      sessionId,
      role.name,
      clean,
      jsonEncode(sources.map((source) => source.toJson()).toList()),
      now.toIso8601String(),
    ]);
    db.database.execute(
      'UPDATE ai_chat_sessions SET updated_at = ? WHERE id = ?;',
      [now.toIso8601String(), sessionId],
    );

    if (role == AiChatRole.user) {
      final title = clean.replaceAll(RegExp(r'\s+'), ' ');
      final shortTitle =
          title.length <= 72 ? title : '${title.substring(0, 72)}…';
      db.database.execute('''
        UPDATE ai_chat_sessions
        SET title = CASE
          WHEN title LIKE 'Chat%' THEN ?
          ELSE title
        END
        WHERE id = ?;
      ''', [shortTitle, sessionId]);
    }

    return AiChatMessage(
      id: id,
      sessionId: sessionId,
      role: role,
      content: clean,
      sources: sources,
      createdAt: now,
    );
  }

  Future<void> clearSession(String sessionId) async {
    db.database.execute(
      'DELETE FROM ai_chat_sessions WHERE id = ?;',
      [sessionId],
    );
  }

  AiChatSession _sessionFromRow(dynamic row) => AiChatSession(
        id: row['id'] as String,
        scope: AiChatScope.values.firstWhere(
          (value) => value.name == row['scope'],
          orElse: () => AiChatScope.library,
        ),
        documentId: row['document_id'] as String?,
        documentTitle: row['document_title'] as String?,
        title: row['title'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  AiChatMessage _messageFromRow(dynamic row) {
    List<AiChatSource> sources = const [];
    try {
      sources = (jsonDecode(row['sources_json'] as String? ?? '[]') as List)
          .whereType<Map>()
          .map(
            (value) => AiChatSource.fromJson(
              value.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      sources = const [];
    }
    return AiChatMessage(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      role: AiChatRole.values.firstWhere(
        (value) => value.name == row['role'],
        orElse: () => AiChatRole.assistant,
      ),
      content: row['content'] as String? ?? '',
      sources: sources,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
