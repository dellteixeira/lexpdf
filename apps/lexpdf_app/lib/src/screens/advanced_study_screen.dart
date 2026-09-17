import 'dart:async';

import 'package:flutter/material.dart';

import '../core/storage/local_advanced_study_store.dart';
import '../core/study/advanced_study_models.dart';

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
  int _refreshToken = 0;
  List<StudySourceHit> _sourceHits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _refreshToken++);

  Future<void> _searchSources() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _sourceHits = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final hits = await widget.store.searchSources(query);
      if (mounted) setState(() => _sourceHits = hits);
    } finally {
      if (mounted) setState(() => _searching = false);
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
        builder: (_) => _StudyReviewScreen(
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
                    const SizedBox(height: 10),
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

class _StudyReviewScreen extends StatefulWidget {
  const _StudyReviewScreen({
    required this.store,
    required this.items,
    this.onOpenSource,
  });

  final LocalAdvancedStudyStore store;
  final List<StudyItem> items;
  final Future<void> Function(String documentId, int pageNumber)? onOpenSource;

  @override
  State<_StudyReviewScreen> createState() => _StudyReviewScreenState();
}

class _StudyReviewScreenState extends State<_StudyReviewScreen> {
  int _index = 0;
  bool _revealed = false;
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
    final item = widget.items[_index];
    await widget.store.recordReview(
      itemId: item.id,
      grade: grade,
      sessionId: _sessionId,
    );
    if (!mounted) return;
    if (_index + 1 >= widget.items.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
    });
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
                              onPressed: () => _grade(StudyReviewGrade.again),
                              child: const Text('Errei'),
                            ),
                            OutlinedButton(
                              onPressed: () => _grade(StudyReviewGrade.hard),
                              child: const Text('Difícil'),
                            ),
                            FilledButton.tonal(
                              onPressed: () => _grade(StudyReviewGrade.good),
                              child: const Text('Bom'),
                            ),
                            FilledButton(
                              onPressed: () => _grade(StudyReviewGrade.easy),
                              child: const Text('Fácil'),
                            ),
                          ],
                        ),
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
