import 'dart:async';

import 'package:flutter/material.dart';
import '../core/ai/ai_access_session.dart';
import '../core/ai/ai_input_policy.dart';
import '../core/ai/ai_models.dart';
import '../core/ai/extended_hybrid_rag_service.dart';
import '../core/ai/hybrid_rag_service.dart';
import '../core/ai/local_embedding_service.dart';
import '../core/ai/local_grounded_answer_engine.dart';
import '../core/ai/remote_ai_engine.dart';
import '../core/backend/backend_config.dart';
import '../core/storage/local_advanced_study_store.dart';
import '../core/storage/local_hybrid_rag_store.dart';
import '../core/storage/local_knowledge_rag_store.dart';
import '../core/study/advanced_study_models.dart';
import 'ai_context_chat_screen.dart';

class AdvancedStudyScreen extends StatefulWidget {
  const AdvancedStudyScreen({
    required this.store,
    this.onOpenSource,
    super.key,
  });

  final LocalAdvancedStudyStore store;
  final Future<void> Function(String documentId, int pageNumber)? onOpenSource;

  @override
  State<AdvancedStudyScreen> createState() => _AdvancedStudyScreenState();
}

class _AdvancedStudyScreenState extends State<AdvancedStudyScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ragController = TextEditingController();
  int _refreshToken = 0;
  List<StudySourceHit> _sourceHits = const [];
  bool _searching = false;
  bool _crossStudyLoading = false;
  AiStudyResult? _crossStudyResult;
  Object? _crossStudyError;
  bool _ragLoading = false;
  bool _ragIndexing = false;
  double? _ragProgress;
  AiStudyResult? _ragResult;
  Object? _ragError;
  List<HybridRagHit> _ragHits = const [];
  HybridRagIndexStatus? _semanticStatus;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSemanticStatus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _ragController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _refreshToken++);

  LocalHybridRagStore get _hybridStore =>
      LocalHybridRagStore(widget.store.db);

  Future<void> _refreshSemanticStatus() async {
    final status = await _hybridStore.status();
    if (mounted) setState(() => _semanticStatus = status);
  }

  LocalAiEmbeddingService _embeddingService() =>
      const LocalAiEmbeddingService();

  ExtendedHybridRagService _hybridRagService() {
    final embeddings = _embeddingService();
    return ExtendedHybridRagService(
      base: HybridRagService(
        store: _hybridStore,
        embeddings: embeddings,
      ),
      knowledge: LocalKnowledgeRagStore(widget.store.db),
      embeddings: embeddings,
    );
  }

  Future<String?> _onlineAiToken(BackendConfig config) async {
    if (!config.hasAiGateway) return null;
    try {
      return await AiAccessSession.bearerToken(config: config);
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateSemanticIndex() async {
    if (_ragLoading || _ragIndexing) return;
    setState(() {
      _ragError = null;
      _ragIndexing = true;
      _ragProgress = 0;
    });
    try {
      await _hybridRagService().updateIndex(
        onProgress: (progress) {
          if (mounted) setState(() => _ragProgress = progress);
        },
      );
    } catch (error) {
      if (mounted) setState(() => _ragError = error);
    } finally {
      if (mounted) {
        setState(() {
          _ragIndexing = false;
          _ragProgress = null;
        });
      }
      await _refreshSemanticStatus();
    }
  }

  String _libraryRagContext(
    String query,
    List<HybridRagHit> hits,
  ) {
    final parts = <String>['PERGUNTA DO USUÁRIO: $query'];
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      final excerpt = LocalHybridRagStore.ragExcerpt(
        hit.content,
        query,
      );
      parts.add(
        '[F${index + 1}] ${hit.documentTitle} — página ${hit.pageNumber}\n'
        '$excerpt',
      );
    }
    return parts.join('\n\n');
  }

  Future<void> _askLibrary() async {
    final query = _ragController.text.trim();
    if (query.isEmpty || _ragLoading || _ragIndexing) return;
    setState(() {
      _ragLoading = true;
      _ragError = null;
      _ragResult = null;
      _ragHits = const [];
    });

    try {
      const config = BackendConfig.fromEnvironment;
      final token = await _onlineAiToken(config);
      final retrieval = await _hybridRagService().retrieve(
        query,
        limit: 8,
        onIndexProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _ragIndexing = progress < 1;
            _ragProgress = progress < 1 ? progress : null;
          });
        },
      );
      final hits = retrieval.hits;
      if (hits.isEmpty) {
        throw StateError(
          'Nenhum trecho relevante foi encontrado. '
          'Execute OCR/indexação nos PDFs antes de usar o RAG híbrido.',
        );
      }

      AiStudyResult result;
      if (token != null) {
        try {
          result = await RemoteAiStudyEngine(
            endpoint: Uri.parse(config.aiGatewayUrl),
            bearerToken: token,
            inputPolicy: const AiInputPolicy(maxCharacters: 30000),
          ).runExplanation(
            action: AiStudyAction.explain,
            text: _libraryRagContext(
              query,
              hits.take(6).toList(growable: false),
            ),
            explanationDepth: AiExplanationDepth.deep,
            intent: AiExplanationIntent.libraryRag,
          );
        } catch (_) {
          result = const LocalGroundedAnswerEngine().answer(
            query: query,
            hits: hits,
          );
        }
      } else {
        result = const LocalGroundedAnswerEngine().answer(
          query: query,
          hits: hits,
        );
      }

      if (mounted) {
        setState(() {
          _ragHits = hits;
          _ragResult = result;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _ragError = error);
    } finally {
      if (mounted) {
        setState(() {
          _ragLoading = false;
          _ragIndexing = false;
          _ragProgress = null;
        });
      }
      await _refreshSemanticStatus();
    }
  }

  Future<void> _openLibraryChat() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AiContextChatScreen(
            database: widget.store.db,
            onOpenSource: widget.onOpenSource,
          ),
        ),
      );

  Future<void> _searchSources() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _sourceHits = const [];
        _crossStudyResult = null;
        _crossStudyError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _crossStudyResult = null;
      _crossStudyError = null;
    });
    try {
      final hits = await widget.store.searchSources(query);
      if (mounted) setState(() => _sourceHits = hits);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  List<StudySourceHit> get _crossStudySources {
    final result = <StudySourceHit>[];
    final seen = <String>{};
    for (final hit in _sourceHits) {
      final key = '${hit.documentId}:${hit.pageNumber}:${hit.snippet}';
      if (!seen.add(key)) continue;
      result.add(hit);
      if (result.length >= 8) break;
    }
    return result;
  }

  String _crossStudyContext() {
    final query = _searchController.text.trim();
    final sources = _crossStudySources;
    final parts = <String>[
      'TEMA DA BUSCA: $query',
      for (var index = 0; index < sources.length; index++)
        '[F${index + 1}] ${sources[index].documentTitle} — página ${sources[index].pageNumber}\n'
            '${sources[index].snippet.replaceAll(RegExp(r'[‹›]'), '')}',
    ];
    return parts.join('\n\n');
  }

  Future<void> _runCrossStudyAi() async {
    if (_crossStudyLoading || _sourceHits.isEmpty) return;
    setState(() {
      _crossStudyLoading = true;
      _crossStudyError = null;
      _crossStudyResult = null;
    });
    try {
      const config = BackendConfig.fromEnvironment;
      final token = await AiAccessSession.bearerToken(config: config);
      final result = await RemoteAiStudyEngine(
        endpoint: Uri.parse(config.aiGatewayUrl),
        bearerToken: token,
      ).runExplanation(
        action: AiStudyAction.explain,
        text: _crossStudyContext(),
        explanationDepth: AiExplanationDepth.deep,
        intent: AiExplanationIntent.crossStudy,
      );
      if (mounted) setState(() => _crossStudyResult = result);
    } catch (error) {
      if (mounted) setState(() => _crossStudyError = error);
    } finally {
      if (mounted) setState(() => _crossStudyLoading = false);
    }
  }

  Future<void> _startReview() async {
    final due = await widget.store.listDue(limit: 100);
    if (!mounted) return;
    if (due.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma revisão pendente agora.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyReviewScreen(
          store: widget.store,
          items: due,
          onOpenSource: widget.onOpenSource,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final refreshKey = _refreshToken;
    const backendConfig = BackendConfig.fromEnvironment;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo Estudo'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FutureBuilder<StudyDashboardStats>(
            key: ValueKey('stats-$refreshKey'),
            future: widget.store.dashboardStats(),
            builder: (context, snapshot) {
              final stats = snapshot.data;
              if (stats == null) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              return _DashboardCard(stats: stats, onReview: _startReview);
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Perguntar à biblioteca — RAG híbrido',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_semanticStatus != null)
                        Text(
                          '${_semanticStatus!.indexedChunks} trechos • '
                          '${_semanticStatus!.indexedPages}/'
                          '${_semanticStatus!.sourcePages} páginas',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Combina PDFs, anotações, cadernos e descrições visuais com '
                    'FTS5, embeddings locais, índice vetorial LSH, chunking e reranking. '
                    'Funciona offline; síntese online é opcional.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ragController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_askLibrary()),
                    decoration: const InputDecoration(
                      labelText: 'Pergunte aos seus PDFs…',
                      hintText:
                          'Ex.: Compare prisão preventiva e prisão temporária nos meus materiais.',
                      prefixIcon: Icon(Icons.psychology_alt_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _ragLoading ||
                                _ragIndexing ||
                                !backendConfig.hasAiGateway
                            ? null
                            : _askLibrary,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Perguntar à biblioteca'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _ragLoading ||
                                _ragIndexing ||
                                !backendConfig.hasAiGateway
                            ? null
                            : _updateSemanticIndex,
                        icon: const Icon(Icons.hub_outlined),
                        label: const Text('Atualizar índice híbrido'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _ragLoading || _ragIndexing
                            ? null
                            : _openLibraryChat,
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Chat com a biblioteca'),
                      ),
                    ],
                  ),
                  if (_ragIndexing) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _ragProgress),
                    const SizedBox(height: 6),
                    Text(
                      _ragProgress == null
                          ? 'Preparando índice híbrido…'
                          : 'Indexando trechos híbridos '
                              '${(_ragProgress! * 100).round()}%…',
                    ),
                  ],
                  if (_ragLoading && !_ragIndexing) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text('Recuperando fontes e preparando resposta…'),
                  ],
                  if (!backendConfig.hasAiGateway) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'O RAG exige o gateway de IA; a busca textual tradicional '
                      'abaixo continua disponível localmente.',
                    ),
                  ],
                  if (_ragError != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('Não foi possível consultar a biblioteca'),
                        subtitle: Text('$_ragError'),
                      ),
                    ),
                  ],
                  if (_ragResult?.text?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Resposta baseada na biblioteca',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                if (_ragResult!.fallbackUsed)
                                  const Tooltip(
                                    message:
                                        'O modelo alternativo foi usado automaticamente.',
                                    child: Icon(Icons.swap_horiz, size: 20),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SelectableText(_ragResult!.text!),
                            if (_ragResult!.quotaRemaining != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Saldo de IA hoje: '
                                '${_ragResult!.quotaRemaining} créditos'
                                '${_ragResult!.quotaLimit == null ? '' : ' de ${_ragResult!.quotaLimit}'}.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 8),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Fontes recuperadas'),
                              subtitle: const Text(
                                'Os marcadores [F1], [F2]… apontam para as '
                                'páginas usadas na resposta.',
                              ),
                              children: [
                                for (var index = 0;
                                    index < _ragHits.take(6).length;
                                    index++)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      child: Text('F${index + 1}'),
                                    ),
                                    title: Text(_ragHits[index].documentTitle),
                                    subtitle: Text(
                                      '${_ragHits[index].locationLabel ?? 'Página ${_ragHits[index].pageNumber}'}\n'
                                      '${LocalHybridRagStore.ragExcerpt(
                                        _ragHits[index].content,
                                        _ragController.text,
                                        maxCharacters: 420,
                                      )}',
                                    ),
                                    isThreeLine: true,
                                    trailing: widget.onOpenSource == null ||
                                            !_ragHits[index].canOpenPdf
                                        ? null
                                        : const Icon(Icons.open_in_new),
                                    onTap: widget.onOpenSource == null ||
                                            !_ragHits[index].canOpenPdf
                                        ? null
                                        : () => widget.onOpenSource!(
                                              _ragHits[index].pdfDocumentId!,
                                              _ragHits[index].pageNumber,
                                            ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estudo cruzado entre PDFs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Busca o conteúdo indexado por OCR/texto em todos os PDFs e mantém a página de origem.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_searchSources()),
                    decoration: InputDecoration(
                      labelText: 'Buscar assunto, artigo, conceito…',
                      prefixIcon: const Icon(Icons.manage_search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Buscar',
                              onPressed: _searchSources,
                              icon: const Icon(Icons.search),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_sourceHits.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _searching ||
                                  _crossStudyLoading ||
                                  !backendConfig.hasAiGateway
                              ? null
                              : _runCrossStudyAi,
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Sintetizar com IA'),
                        ),
                        Text(
                          'A IA usa até ${_crossStudySources.length} trechos encontrados e mantém as referências [F1], [F2]…',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (!backendConfig.hasAiGateway) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'A busca cruzada continua disponível offline; a síntese exige o gateway de IA configurado.',
                      ),
                    ],
                    if (_crossStudyLoading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_crossStudyError != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: const Text('Não foi possível gerar a síntese cruzada'),
                          subtitle: Text('$_crossStudyError'),
                        ),
                      ),
                    ],
                    if (_crossStudyResult?.text?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Síntese cruzada',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (_crossStudyResult!.fallbackUsed)
                                    const Tooltip(
                                      message: 'O modelo alternativo foi usado automaticamente.',
                                      child: Icon(Icons.swap_horiz, size: 20),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SelectableText(_crossStudyResult!.text!),
                              if (_crossStudyResult!.quotaRemaining != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Saldo de IA hoje: ${_crossStudyResult!.quotaRemaining} créditos'
                                  '${_crossStudyResult!.quotaLimit == null ? '' : ' de ${_crossStudyResult!.quotaLimit}'}.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 8),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('Fontes consideradas'),
                                subtitle: const Text(
                                  'Os marcadores [F1], [F2]… da síntese correspondem a estas páginas.',
                                ),
                                children: [
                                  for (var index = 0;
                                      index < _crossStudySources.length;
                                      index++)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        child: Text('F${index + 1}'),
                                      ),
                                      title: Text(
                                        _crossStudySources[index].documentTitle,
                                      ),
                                      subtitle: Text(
                                        'Página ${_crossStudySources[index].pageNumber}\n'
                                        '${_crossStudySources[index].snippet}',
                                      ),
                                      isThreeLine: true,
                                      trailing: widget.onOpenSource == null
                                          ? null
                                          : const Icon(Icons.open_in_new),
                                      onTap: widget.onOpenSource == null
                                          ? null
                                          : () => widget.onOpenSource!(
                                                _crossStudySources[index].documentId,
                                                _crossStudySources[index].pageNumber,
                                              ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 28),
                    for (final hit in _sourceHits)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(hit.documentTitle),
                        subtitle: Text('Página ${hit.pageNumber}\n${hit.snippet}'),
                        isThreeLine: true,
                        trailing: widget.onOpenSource == null
                            ? null
                            : const Icon(Icons.open_in_new),
                        onTap: widget.onOpenSource == null
                            ? null
                            : () => widget.onOpenSource!(
                                  hit.documentId,
                                  hit.pageNumber,
                                ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Materiais de estudo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<StudyItem>>(
            key: ValueKey('items-$refreshKey'),
            future: widget.store.listItems(limit: 300),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ));
              }
              final items = snapshot.data ?? const <StudyItem>[];
              if (items.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.school_outlined),
                    title: Text('Nenhum material estruturado ainda'),
                    subtitle: Text(
                      'Selecione um trecho no PDF e use Flashcard, Questão, Explicar ou Resumir; ao salvar no caderno, ele entra aqui automaticamente.',
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        leading: Icon(_iconFor(item.kind)),
                        title: Text(item.prompt.isEmpty ? _labelFor(item.kind) : item.prompt),
                        subtitle: Text(
                          [
                            if (item.answer.isNotEmpty) item.answer,
                            if (item.documentTitle != null)
                              'Fonte: ${item.documentTitle}${item.sourcePage == null ? '' : ' • pág. ${item.sourcePage}'}',
                            if (item.subject.isNotEmpty) 'Assunto: ${item.subject}',
                            if (item.tags.isNotEmpty) 'Tags: ${item.tags.join(', ')}',
                          ].join('\n'),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: item.documentId != null &&
                                item.sourcePage != null &&
                                widget.onOpenSource != null
                            ? IconButton(
                                tooltip: 'Abrir fonte',
                                onPressed: () => widget.onOpenSource!(
                                  item.documentId!,
                                  item.sourcePage!,
                                ),
                                icon: const Icon(Icons.open_in_new),
                              )
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(StudyItemKind kind) {
    switch (kind) {
      case StudyItemKind.flashcard:
        return Icons.style_outlined;
      case StudyItemKind.question:
        return Icons.quiz_outlined;
      case StudyItemKind.explanation:
        return Icons.lightbulb_outline;
      case StudyItemKind.summary:
        return Icons.summarize_outlined;
    }
  }

  static String _labelFor(StudyItemKind kind) {
    switch (kind) {
      case StudyItemKind.flashcard:
        return 'Flashcard';
      case StudyItemKind.question:
        return 'Questão';
      case StudyItemKind.explanation:
        return 'Explicação';
      case StudyItemKind.summary:
        return 'Resumo';
    }
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.stats, required this.onReview});

  final StudyDashboardStats stats;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Painel de revisão',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: stats.dueItems == 0 ? null : onReview,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Revisar ${stats.dueItems}'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(label: 'Itens', value: '${stats.totalItems}'),
                _Metric(label: 'Pendentes', value: '${stats.dueItems}'),
                _Metric(label: 'Revisados hoje', value: '${stats.reviewedToday}'),
                _Metric(
                  label: 'Acerto hoje',
                  value: '${(stats.accuracyToday * 100).round()}%',
                ),
                _Metric(label: 'Sequência', value: '${stats.streakDays} d'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label),
          ],
        ),
      );
}

class StudyReviewScreen extends StatefulWidget {
  const StudyReviewScreen({
    required this.store,
    required this.items,
    this.onOpenSource,
  });

  final LocalAdvancedStudyStore store;
  final List<StudyItem> items;
  final Future<void> Function(String documentId, int pageNumber)? onOpenSource;

  @override
  State<StudyReviewScreen> createState() => StudyReviewScreenState();
}

class StudyReviewScreenState extends State<StudyReviewScreen> {
  int _index = 0;
  bool _revealed = false;
  bool _reviewTutorLoading = false;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  Future<void> _begin() async {
    final id = await widget.store.startSession();
    if (mounted) setState(() => _sessionId = id);
  }

  @override
  void dispose() {
    final id = _sessionId;
    if (id != null) unawaited(widget.store.finishSession(id));
    super.dispose();
  }

  Future<void> _grade(StudyReviewGrade grade) async {
    if (_reviewTutorLoading) return;
    final item = widget.items[_index];
    await widget.store.recordReview(
      itemId: item.id,
      grade: grade,
      sessionId: _sessionId,
    );
    if (!mounted) return;

    final needsTutor = item.kind == StudyItemKind.flashcard &&
        (grade == StudyReviewGrade.again ||
            grade == StudyReviewGrade.hard);
    if (needsTutor) {
      await _showReviewTutor(item, grade);
      if (!mounted) return;
    }
    _advanceReview();
  }

  void _advanceReview() {
    if (_index + 1 >= widget.items.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
    });
  }

  String _reviewTutorContext(StudyItem item, StudyReviewGrade grade) {
    final gradeLabel =
        grade == StudyReviewGrade.again ? 'ERREI' : 'DIFÍCIL';
    return [
      'RESULTADO DA REVISÃO: $gradeLabel',
      'PERGUNTA DO FLASHCARD:\n${item.prompt}',
      'RESPOSTA DO FLASHCARD:\n${item.answer}',
      if (item.sourceText.trim().isNotEmpty)
        'TRECHO-FONTE ORIGINAL:\n${item.sourceText.trim()}',
      if (item.documentTitle?.trim().isNotEmpty == true)
        'DOCUMENTO DE ORIGEM: ${item.documentTitle}'
            '${item.sourcePage == null ? '' : ' — página ${item.sourcePage}'}',
    ].join('\n\n');
  }

  Future<void> _showReviewTutor(
    StudyItem item,
    StudyReviewGrade grade,
  ) async {
    setState(() => _reviewTutorLoading = true);
    try {
      const config = BackendConfig.fromEnvironment;
      final token = await AiAccessSession.bearerToken(config: config);

      final result = await RemoteAiStudyEngine(
        endpoint: Uri.parse(config.aiGatewayUrl),
        bearerToken: token,
      ).runExplanation(
        action: AiStudyAction.explain,
        text: _reviewTutorContext(item, grade),
        explanationDepth: AiExplanationDepth.detailed,
        intent: AiExplanationIntent.reviewTutor,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            grade == StudyReviewGrade.again
                ? 'Tutor IA — Errei'
                : 'Tutor IA — Difícil',
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'O flashcard original não foi alterado. '
                    'A resposta abaixo é apenas um reforço para esta revisão.',
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    result.text?.trim().isNotEmpty == true
                        ? result.text!
                        : 'A IA não retornou conteúdo de reforço.',
                  ),
                  if (result.quotaRemaining != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Saldo de IA hoje: ${result.quotaRemaining} créditos'
                      '${result.quotaLimit == null ? '' : ' de ${result.quotaLimit}'}.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (item.documentId != null &&
                item.sourcePage != null &&
                widget.onOpenSource != null)
              TextButton.icon(
                onPressed: () => widget.onOpenSource!(
                  item.documentId!,
                  item.sourcePage!,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir página original'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar e continuar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Revisão registrada. O Tutor IA não pôde ser aberto: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewTutorLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('Revisão ${_index + 1}/${widget.items.length}'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.prompt.isEmpty ? 'Material de estudo' : item.prompt,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (item.documentTitle != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Fonte: ${item.documentTitle}${item.sourcePage == null ? '' : ' • pág. ${item.sourcePage}'}',
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (!_revealed)
                        FilledButton.icon(
                          onPressed: () => setState(() => _revealed = true),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Mostrar resposta'),
                        )
                      else ...[
                        SelectableText(
                          item.answer.isEmpty
                              ? 'Revise o enunciado e marque sua percepção de dificuldade.'
                              : item.answer,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (item.sourceText.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Trecho-fonte'),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SelectableText(item.sourceText),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _reviewTutorLoading
                                  ? null
                                  : () => unawaited(
                                        _grade(StudyReviewGrade.again),
                                      ),
                              child: const Text('Errei'),
                            ),
                            OutlinedButton(
                              onPressed: _reviewTutorLoading
                                  ? null
                                  : () => unawaited(
                                        _grade(StudyReviewGrade.hard),
                                      ),
                              child: const Text('Difícil'),
                            ),
                            FilledButton.tonal(
                              onPressed: _reviewTutorLoading
                                  ? null
                                  : () => unawaited(
                                        _grade(StudyReviewGrade.good),
                                      ),
                              child: const Text('Bom'),
                            ),
                            FilledButton(
                              onPressed: _reviewTutorLoading
                                  ? null
                                  : () => unawaited(
                                        _grade(StudyReviewGrade.easy),
                                      ),
                              child: const Text('Fácil'),
                            ),
                          ],
                        ),
                        if (_reviewTutorLoading) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          const Text(
                            'Preparando reforço com o Tutor IA…',
                          ),
                        ],
                      ],
                      if (item.documentId != null &&
                          item.sourcePage != null &&
                          widget.onOpenSource != null) ...[
                        const SizedBox(height: 18),
                        TextButton.icon(
                          onPressed: () => widget.onOpenSource!(
                            item.documentId!,
                            item.sourcePage!,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir página original'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
