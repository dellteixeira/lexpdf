import 'dart:async';

import 'package:flutter/material.dart';

import '../core/storage/local_advanced_study_store.dart';
import '../core/study/advanced_study_models.dart';
import 'advanced_study_screen.dart';

class FlashcardCenterScreen extends StatefulWidget {
  const FlashcardCenterScreen({
    required this.store,
    this.onOpenSource,
    this.embedded = false,
    super.key,
  });

  final LocalAdvancedStudyStore store;
  final Future<void> Function(String documentId, int pageNumber)? onOpenSource;
  final bool embedded;

  @override
  State<FlashcardCenterScreen> createState() => _FlashcardCenterScreenState();
}

class _FlashcardCenterScreenState extends State<FlashcardCenterScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<FlashcardLibraryEntry> _entries = const [];
  bool _loading = true;
  FlashcardLibraryFilter _filter = FlashcardLibraryFilter.all;
  String? _selectedSubject;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    final entries = await widget.store.listFlashcardEntries(limit: 20000);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
      final subjects = _subjects(entries);
      if (_selectedSubject != null && !subjects.contains(_selectedSubject)) {
        _selectedSubject = null;
      }
    });
  }

  List<String> _subjects(List<FlashcardLibraryEntry> entries) {
    final result = entries.map((entry) => entry.subject).toSet().toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  List<FlashcardLibraryEntry> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return _entries.where((entry) {
      if (_selectedSubject != null && entry.subject != _selectedSubject) {
        return false;
      }
      final matchesFilter = switch (_filter) {
        FlashcardLibraryFilter.all => true,
        FlashcardLibraryFilter.due => entry.isDue,
        FlashcardLibraryFilter.newCards => entry.isNew,
        FlashcardLibraryFilter.difficult => entry.isDifficult,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      final item = entry.item;
      final haystack = [
        item.prompt,
        item.answer,
        item.sourceText,
        item.documentTitle ?? '',
        entry.subject,
        entry.topic,
        ...item.tags,
      ].join('\n').toLowerCase();
      return query
          .split(RegExp(r'\s+'))
          .where((term) => term.isNotEmpty)
          .every(haystack.contains);
    }).toList(growable: false);
  }

  int _count(bool Function(FlashcardLibraryEntry entry) predicate) =>
      _entries.where(predicate).length;

  Future<void> _startReview(
    Iterable<FlashcardLibraryEntry> entries, {
    bool dueOnly = false,
  }) async {
    final items = entries
        .where((entry) => !dueOnly || entry.isDue)
        .map((entry) => entry.item)
        .toList(growable: false);
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum cartão disponível neste filtro.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyReviewScreen(
          store: widget.store,
          items: items,
          onOpenSource: widget.onOpenSource,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _organize(FlashcardLibraryEntry entry) async {
    final subject = TextEditingController(
      text: entry.item.subject.trim().isEmpty
          ? entry.subject
          : entry.item.subject,
    );
    final topic = TextEditingController(
      text: entry.item.topic.trim().isEmpty ? entry.topic : entry.item.topic,
    );
    final tags = TextEditingController(text: entry.item.tags.join(', '));
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Organizar flashcard'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: subject,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Matéria',
                    hintText: 'Ex.: Direito Constitucional',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: topic,
                  decoration: const InputDecoration(
                    labelText: 'Assunto',
                    hintText: 'Ex.: Controle de constitucionalidade',
                    prefixIcon: Icon(Icons.topic_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'FCC, art. 5º, jurisprudência',
                    prefixIcon: Icon(Icons.sell_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar organização'),
            ),
          ],
        ),
      );
      if (save != true) return;
      await widget.store.updateFlashcardClassification(
        itemId: entry.item.id,
        subject: subject.text,
        topic: topic.text,
        tags: tags.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false),
      );
      await _reload();
    } finally {
      subject.dispose();
      topic.dispose();
      tags.dispose();
    }
  }

  Future<void> _delete(FlashcardLibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir flashcard?'),
        content: Text(
          entry.item.prompt.isEmpty
              ? 'Este cartão será excluído.'
              : '“${entry.item.prompt}” será excluído.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteFlashcard(entry.item.id);
    await _reload();
  }

  Future<void> _showCard(FlashcardLibraryEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.item.prompt),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  entry.item.answer,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.menu_book_outlined, size: 17),
                      label: Text(entry.subject),
                    ),
                    Chip(
                      avatar: const Icon(Icons.topic_outlined, size: 17),
                      label: Text(entry.topic),
                    ),
                    if (entry.isDue) const Chip(label: Text('Para revisar')),
                    if (entry.isNew) const Chip(label: Text('Novo')),
                    if (entry.isDifficult)
                      const Chip(label: Text('Precisa de atenção')),
                  ],
                ),
                if (entry.item.documentTitle != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Fonte: ${entry.item.documentTitle}'
                    '${entry.item.sourcePage == null ? '' : ' • pág. ${entry.item.sourcePage}'}',
                  ),
                ],
                if (entry.item.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Tags: ${entry.item.tags.join(', ')}'),
                ],
                if (entry.item.sourceText.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Trecho-fonte'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(entry.item.sourceText),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_organize(entry));
            },
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('Organizar'),
          ),
          if (entry.item.documentId != null &&
              entry.item.sourcePage != null &&
              widget.onOpenSource != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  widget.onOpenSource!(
                    entry.item.documentId!,
                    entry.item.sourcePage!,
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir fonte'),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_startReview([entry]));
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Estudar'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (value) {
              Navigator.of(dialogContext).pop();
              if (value == 'delete') unawaited(_delete(entry));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('Excluir flashcard'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Central de Flashcards'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _filtered;
    final subjects = _subjects(_entries);
    final dueCount = _count((entry) => entry.isDue);
    final newCount = _count((entry) => entry.isNew);
    final difficultCount = _count((entry) => entry.isDifficult);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 920;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FlashcardSummary(
              total: _entries.length,
              due: dueCount,
              newCards: newCount,
              difficult: difficultCount,
              onReviewDue: dueCount == 0
                  ? null
                  : () => unawaited(_startReview(_entries, dueOnly: true)),
            ),
            const SizedBox(height: 14),
            _buildControls(subjects, desktop: desktop),
            const SizedBox(height: 12),
            Expanded(
              child: _entries.isEmpty
                  ? const _FlashcardEmptyState()
                  : desktop
                      ? _buildDesktop(visible, subjects)
                      : _buildTopics(visible),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(List<String> subjects, {required bool desktop}) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: 'Pesquisar todos os flashcards',
            hintText: 'Pergunta, resposta, matéria, assunto, tag ou PDF…',
            border: const OutlineInputBorder(),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(FlashcardLibraryFilter.all, 'Todos', _entries.length),
              _filterChip(
                FlashcardLibraryFilter.due,
                'Para revisar',
                _count((entry) => entry.isDue),
              ),
              _filterChip(
                FlashcardLibraryFilter.newCards,
                'Novos',
                _count((entry) => entry.isNew),
              ),
              _filterChip(
                FlashcardLibraryFilter.difficult,
                'Difíceis',
                _count((entry) => entry.isDifficult),
              ),
              if (!desktop)
                PopupMenuButton<String>(
                  tooltip: 'Filtrar matéria',
                  initialValue: _selectedSubject ?? '__all__',
                  onSelected: (value) => setState(
                    () => _selectedSubject =
                        value == '__all__' ? null : value,
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem<String>(
                      value: '__all__',
                      child: Text('Todas as matérias'),
                    ),
                    for (final subject in subjects)
                      PopupMenuItem<String>(
                        value: subject,
                        child: Text(subject),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(_selectedSubject ?? 'Todas as matérias'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(
    FlashcardLibraryFilter value,
    String label,
    int count,
  ) {
    return ChoiceChip(
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
      label: Text('$label · $count'),
    );
  }

  Widget _buildDesktop(
    List<FlashcardLibraryEntry> visible,
    List<String> subjects,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 260,
          child: Card(
            margin: EdgeInsets.zero,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  selected: _selectedSubject == null,
                  leading: const Icon(Icons.all_inbox_outlined),
                  title: const Text('Todas as matérias'),
                  trailing: _CountBadge(value: _entries.length),
                  onTap: () => setState(() => _selectedSubject = null),
                ),
                for (final subject in subjects)
                  ListTile(
                    selected: _selectedSubject == subject,
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(
                      subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _CountBadge(
                      value:
                          _entries.where((entry) => entry.subject == subject).length,
                    ),
                    onTap: () => setState(() => _selectedSubject = subject),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: _buildTopics(visible)),
      ],
    );
  }

  Widget _buildTopics(List<FlashcardLibraryEntry> entries) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('Nenhum flashcard corresponde aos filtros atuais.'),
      );
    }

    final groups = <String, List<FlashcardLibraryEntry>>{};
    for (final entry in entries) {
      final key = '${entry.subject}\u0000${entry.topic}';
      groups.putIfAbsent(key, () => []).add(entry);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final group = groups[keys[index]]!;
        final entry = group.first;
        final due = group.where((item) => item.isDue).length;
        return Card(
          child: ExpansionTile(
            initiallyExpanded: keys.length <= 4,
            leading: const Icon(Icons.topic_outlined),
            title: Text(entry.topic),
            subtitle: Text(
              '${entry.subject} • ${group.length} cartão(ões)'
              '${due == 0 ? '' : ' • $due para revisar'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (due > 0)
                  IconButton(
                    tooltip: 'Revisar $due pendente(s)',
                    onPressed: () =>
                        unawaited(_startReview(group, dueOnly: true)),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                const Icon(Icons.expand_more),
              ],
            ),
            children: [
              for (final card in group)
                _FlashcardListTile(
                  entry: card,
                  onTap: () => _showCard(card),
                  onOrganize: () => _organize(card),
                  onStudy: () => _startReview([card]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FlashcardSummary extends StatelessWidget {
  const _FlashcardSummary({
    required this.total,
    required this.due,
    required this.newCards,
    required this.difficult,
    required this.onReviewDue,
  });

  final int total;
  final int due;
  final int newCards;
  final int difficult;
  final VoidCallback? onReviewDue;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetricBox(label: 'Cartões', value: total, icon: Icons.style_outlined),
            _MetricBox(
              label: 'Para revisar',
              value: due,
              icon: Icons.schedule_outlined,
            ),
            _MetricBox(
              label: 'Novos',
              value: newCards,
              icon: Icons.fiber_new_outlined,
            ),
            _MetricBox(
              label: 'Difíceis',
              value: difficult,
              icon: Icons.priority_high,
            ),
            FilledButton.icon(
              onPressed: onReviewDue,
              icon: const Icon(Icons.play_arrow),
              label: Text(due == 0 ? 'Nada pendente' : 'Revisar agora · $due'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(label),
              ],
            ),
          ],
        ),
      );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
}

class _FlashcardListTile extends StatelessWidget {
  const _FlashcardListTile({
    required this.entry,
    required this.onTap,
    required this.onOrganize,
    required this.onStudy,
  });

  final FlashcardLibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onOrganize;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final status = entry.isDue
        ? 'Para revisar'
        : entry.isNew
            ? 'Novo'
            : entry.isDifficult
                ? 'Difícil'
                : 'Em dia';
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      leading: const Icon(Icons.style_outlined),
      title: Text(
        entry.item.prompt,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          status,
          if (entry.item.documentTitle != null) entry.item.documentTitle!,
          if (entry.item.sourcePage != null) 'pág. ${entry.item.sourcePage}',
        ].join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Organizar',
            onPressed: onOrganize,
            icon: const Icon(Icons.drive_file_move_outline),
          ),
          IconButton(
            tooltip: 'Estudar cartão',
            onPressed: onStudy,
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _FlashcardEmptyState extends StatelessWidget {
  const _FlashcardEmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style_outlined, size: 58),
              const SizedBox(height: 14),
              Text(
                'Nenhum flashcard salvo ainda',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Selecione um trecho em qualquer PDF e escolha Flashcard. '
                'Todos os cartões aparecerão automaticamente aqui.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
