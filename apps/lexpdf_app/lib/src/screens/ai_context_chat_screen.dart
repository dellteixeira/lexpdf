import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai/ai_input_policy.dart';
import '../core/ai/ai_models.dart';
import '../core/ai/hybrid_rag_service.dart';
import '../core/ai/remote_ai_engine.dart';
import '../core/ai/remote_embedding_service.dart';
import '../core/backend/backend_config.dart';
import '../core/storage/local_ai_chat_store.dart';
import '../core/storage/local_database.dart';
import '../core/storage/local_hybrid_rag_store.dart';

class AiContextChatScreen extends StatefulWidget {
  const AiContextChatScreen({
    required this.database,
    this.documentId,
    this.documentTitle,
    this.onOpenSource,
    this.popAfterSourceOpen = false,
    super.key,
  });

  final LocalDatabase database;
  final String? documentId;
  final String? documentTitle;
  final Future<void> Function(String documentId, int pageNumber)? onOpenSource;
  final bool popAfterSourceOpen;

  bool get isDocumentChat => documentId != null;

  @override
  State<AiContextChatScreen> createState() => _AiContextChatScreenState();
}

class _AiContextChatScreenState extends State<AiContextChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late final LocalAiChatStore _chatStore;
  AiChatSession? _session;
  List<AiChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _indexing = false;
  double? _indexProgress;
  Object? _error;

  AiChatScope get _scope =>
      widget.isDocumentChat ? AiChatScope.document : AiChatScope.library;

  @override
  void initState() {
    super.initState();
    _chatStore = LocalAiChatStore(widget.database);
    unawaited(_loadConversation());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    try {
      final latest = await _chatStore.latestSession(
        scope: _scope,
        documentId: widget.documentId,
      );
      final session = latest ??
          await _chatStore.createSession(
            scope: _scope,
            documentId: widget.documentId,
            documentTitle: widget.documentTitle,
          );
      final messages = await _chatStore.listMessages(session.id);
      if (!mounted) return;
      setState(() {
        _session = session;
        _messages = messages;
        _loading = false;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _newConversation() async {
    if (_sending) return;
    final session = await _chatStore.createSession(
      scope: _scope,
      documentId: widget.documentId,
      documentTitle: widget.documentTitle,
    );
    if (!mounted) return;
    setState(() {
      _session = session;
      _messages = const [];
      _error = null;
    });
  }

  String _requireToken(BackendConfig config) {
    if (!config.hasAiGateway) {
      throw StateError('O gateway de IA não está configurado neste build.');
    }
    if (!config.hasSupabase) {
      throw StateError('A autenticação LexPDF não está configurada.');
    }
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Entre na sua conta LexPDF para usar o chat com IA.');
    }
    return token;
  }

  RemoteAiEmbeddingService _embeddingService(
    BackendConfig config,
    String token,
  ) {
    final explain = Uri.parse(config.aiGatewayUrl);
    return RemoteAiEmbeddingService(
      endpoint: explain.replace(
        path: '/v1/ai/embed',
        query: null,
        fragment: null,
      ),
      bearerToken: token,
    );
  }

  String _chatContext(
    String query,
    List<AiChatMessage> history,
    List<HybridRagHit> hits,
  ) {
    final parts = <String>[
      'HISTÓRICO DA CONVERSA (somente para continuidade):',
    ];
    if (history.isEmpty) {
      parts.add('(sem histórico anterior)');
    } else {
      for (final message in history) {
        final role =
            message.role == AiChatRole.user ? 'USUÁRIO' : 'ASSISTENTE';
        parts.add('$role: ${message.content}');
      }
    }
    parts.add('PERGUNTA ATUAL: $query');
    parts.add('FONTES ATUAIS:');
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      parts.add(
        '[F${index + 1}] ${hit.documentTitle} — página ${hit.pageNumber}\n'
        '${LocalHybridRagStore.ragExcerpt(hit.content, query)}',
      );
    }
    return parts.join('\n\n');
  }

  Future<void> _send() async {
    final query = _composer.text.trim();
    if (query.isEmpty || _sending || _loading) return;

    var session = _session;
    session ??= await _chatStore.createSession(
      scope: _scope,
      documentId: widget.documentId,
      documentTitle: widget.documentTitle,
    );

    final userMessage = await _chatStore.appendMessage(
      sessionId: session.id,
      role: AiChatRole.user,
      content: query,
    );
    if (!mounted) return;
    _composer.clear();
    setState(() {
      _session = session;
      _messages = [..._messages, userMessage];
      _sending = true;
      _error = null;
      _indexing = false;
      _indexProgress = null;
    });
    _scrollToEnd();

    try {
      const config = BackendConfig.fromEnvironment;
      final token = _requireToken(config);
      final rag = HybridRagService(
        store: LocalHybridRagStore(widget.database),
        embeddings: _embeddingService(config, token),
      );
      final retrieval = await rag.retrieve(
        query,
        documentId: widget.documentId,
        limit: 8,
        onIndexProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _indexing = progress < 1;
            _indexProgress = progress < 1 ? progress : null;
          });
        },
      );
      if (retrieval.hits.isEmpty) {
        throw StateError(
          widget.isDocumentChat
              ? 'Não encontrei trechos pesquisáveis neste PDF. Execute OCR/indexação antes de conversar com o documento.'
              : 'Não encontrei trechos pesquisáveis na biblioteca. Execute OCR/indexação nos PDFs antes de usar o chat.',
        );
      }

      final previous = _messages.length > 1
          ? _messages.sublist(
              _messages.length > 9 ? _messages.length - 9 : 0,
              _messages.length - 1,
            )
          : const <AiChatMessage>[];
      final sources = retrieval.hits
          .take(6)
          .map(
            (hit) => AiChatSource(
              documentId: hit.documentId,
              documentTitle: hit.documentTitle,
              pageNumber: hit.pageNumber,
              excerpt: LocalHybridRagStore.ragExcerpt(
                hit.content,
                query,
                maxCharacters: 700,
              ),
              score: hit.rerankScore,
            ),
          )
          .toList(growable: false);

      final result = await RemoteAiStudyEngine(
        endpoint: Uri.parse(config.aiGatewayUrl),
        bearerToken: token,
        inputPolicy: const AiInputPolicy(maxCharacters: 30000),
      ).runExplanation(
        action: AiStudyAction.explain,
        text: _chatContext(
          query,
          previous,
          retrieval.hits.take(6).toList(growable: false),
        ),
        explanationDepth: AiExplanationDepth.deep,
        intent: AiExplanationIntent.contextChat,
      );
      final answer = result.text?.trim() ?? '';
      if (answer.isEmpty) {
        throw StateError('A IA não retornou uma resposta para esta pergunta.');
      }

      final assistantMessage = await _chatStore.appendMessage(
        sessionId: session.id,
        role: AiChatRole.assistant,
        content: answer,
        sources: sources,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, assistantMessage];
      });
      _scrollToEnd();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _indexing = false;
          _indexProgress = null;
        });
      }
    }
  }

  Future<void> _openSource(AiChatSource source) async {
    final callback = widget.onOpenSource;
    if (callback == null) return;
    await callback(source.documentId, source.pageNumber);
    if (mounted && widget.popAfterSourceOpen) {
      Navigator.of(context).pop();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isDocumentChat
        ? 'Chat com este PDF'
        : 'Chat com a biblioteca';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Nova conversa',
            onPressed: _sending ? null : _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isDocumentChat
                          ? 'RAG híbrido restrito a ${widget.documentTitle ?? 'este PDF'}: FTS5 + embeddings + reranking.'
                          : 'RAG híbrido em toda a biblioteca: FTS5 + embeddings + reranking. Fontes [F#] são recuperadas novamente a cada pergunta.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_indexing) ...[
            LinearProgressIndicator(value: _indexProgress),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _indexProgress == null
                    ? 'Atualizando o índice híbrido…'
                    : 'Atualizando trechos semânticos ${(_indexProgress! * 100).round()}%…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(18),
                    itemCount: _messages.isEmpty ? 1 : _messages.length,
                    itemBuilder: (context, index) {
                      if (_messages.isEmpty) {
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              widget.isDocumentChat
                                  ? 'Pergunte sobre este PDF. O chat mantém o contexto entre as perguntas e cita as páginas usadas.'
                                  : 'Pergunte à sua biblioteca. O chat mantém o contexto da conversa e recupera novas fontes a cada pergunta.',
                            ),
                          ),
                        );
                      }
                      return _ChatBubble(
                        message: _messages[index],
                        onOpenSource: widget.onOpenSource == null
                            ? null
                            : _openSource,
                      );
                    },
                  ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: MaterialBanner(
                content: Text('$_error'),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_send()),
                      decoration: InputDecoration(
                        hintText: widget.isDocumentChat
                            ? 'Pergunte sobre este PDF…'
                            : 'Pergunte à sua biblioteca…',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: _sending ? null : () => unawaited(_send()),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    this.onOpenSource,
  });

  final AiChatMessage message;
  final Future<void> Function(AiChatSource source)? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiChatRole.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'Você' : 'LexPDF IA',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            SelectableText(message.content),
            if (!isUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('Fontes desta resposta (${message.sources.length})'),
                children: [
                  for (var index = 0;
                      index < message.sources.length;
                      index++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text('F${index + 1}'),
                      ),
                      title: Text(message.sources[index].documentTitle),
                      subtitle: Text(
                        'Página ${message.sources[index].pageNumber}\n'
                        '${message.sources[index].excerpt}',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: onOpenSource == null
                          ? null
                          : const Icon(Icons.open_in_new),
                      onTap: onOpenSource == null
                          ? null
                          : () => unawaited(
                                onOpenSource!(message.sources[index]),
                              ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
