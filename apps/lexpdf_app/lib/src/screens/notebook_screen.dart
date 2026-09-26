import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/storage/local_ink_store.dart';
import '../widgets/notebook_cover_card.dart';
import '../widgets/notebook_page_background.dart';
import 'stylus_notebook_editor_screen.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({
    required this.inkStore,
    super.key,
  });

  final LocalInkStore inkStore;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  List<InkNotebook> _notebooks = const [];
  Map<String, int> _pageCounts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final notebooks = await widget.inkStore.listNotebooks();
    final counts = <String, int>{};
    for (final notebook in notebooks) {
      counts[notebook.id] =
          (await widget.inkStore.listPages(notebook.id)).length;
    }
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _pageCounts = counts;
      _loading = false;
    });
  }

  Future<void> _openNotebook(InkNotebook notebook) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StylusNotebookEditorScreen(
          inkStore: widget.inkStore,
          notebook: notebook,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _createNotebook() async {
    final result = await showModalBottomSheet<
        ({
          String title,
          InkNotebookCover cover,
          InkPageFormat format,
          InkPageBackground background,
        })>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _CreateNotebookSheet(),
    );
    if (result == null) return;

    final notebook = await widget.inkStore.createNotebook(
      result.title,
      cover: result.cover,
      firstPageFormat: result.format,
      firstPageBackground: result.background,
    );
    await _reload();
    if (!mounted) return;
    await _openNotebook(notebook);
  }

  Future<void> _renameNotebook(InkNotebook notebook) async {
    final controller = TextEditingController(text: notebook.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear caderno'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    await widget.inkStore.renameNotebook(notebook.id, value);
    await _reload();
  }

  Future<void> _changeCover(InkNotebook notebook) async {
    final cover = await showModalBottomSheet<InkNotebookCover>(
      context: context,
      showDragHandle: true,
      builder: (context) => _CoverPickerSheet(selected: notebook.cover),
    );
    if (cover == null || cover == notebook.cover) return;
    await widget.inkStore.updateNotebookCover(notebook.id, cover);
    await _reload();
  }

  Future<void> _deleteNotebook(InkNotebook notebook) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir caderno?'),
            content: Text(
              '“${notebook.title}” e todas as suas páginas e anotações serão removidos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.inkStore.deleteNotebook(notebook.id);
    await _reload();
  }

  void _handleNotebookAction(String action, InkNotebook notebook) {
    switch (action) {
      case 'rename':
        unawaited(_renameNotebook(notebook));
        break;
      case 'cover':
        unawaited(_changeCover(notebook));
        break;
      case 'delete':
        unawaited(_deleteNotebook(notebook));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadernos'),
        actions: [
          FilledButton.icon(
            onPressed: _createNotebook,
            icon: const Icon(Icons.add),
            label: const Text('Novo caderno'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notebooks.isEmpty
              ? _EmptyNotebookState(onCreate: _createNotebook)
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sua estante',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Cadernos manuscritos locais, otimizados para S Pen e stylus.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 310,
                          crossAxisSpacing: 22,
                          mainAxisSpacing: 22,
                        ),
                        itemCount: _notebooks.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _NewNotebookCard(onTap: _createNotebook);
                          }
                          final notebook = _notebooks[index - 1];
                          final pages = _pageCounts[notebook.id] ?? 0;
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: NotebookCoverCard(
                                  cover: notebook.cover,
                                  title: notebook.title,
                                  subtitle: '$pages ${pages == 1 ? 'página' : 'páginas'}',
                                  onTap: () => _openNotebook(notebook),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: PopupMenuButton<String>(
                                  tooltip: 'Opções do caderno',
                                  iconColor: Colors.white,
                                  color: scheme.surface,
                                  onSelected: (value) =>
                                      _handleNotebookAction(value, notebook),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: ListTile(
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('Renomear'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'cover',
                                      child: ListTile(
                                        leading: Icon(Icons.palette_outlined),
                                        title: Text('Trocar capa'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        leading: Icon(Icons.delete_outline),
                                        title: Text('Excluir'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _EmptyNotebookState extends StatelessWidget {
  const _EmptyNotebookState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 70,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Crie seu primeiro caderno',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Escolha capa, tamanho e tipo de papel. Depois escreva diretamente com a caneta.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Novo caderno'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewNotebookCard extends StatelessWidget {
  const _NewNotebookCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.add,
                size: 32,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Novo caderno',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              'Capa + papel + tamanho',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateNotebookSheet extends StatefulWidget {
  const _CreateNotebookSheet();

  @override
  State<_CreateNotebookSheet> createState() => _CreateNotebookSheetState();
}

class _CreateNotebookSheetState extends State<_CreateNotebookSheet> {
  final TextEditingController _title = TextEditingController();

  InkNotebookCover _cover = InkNotebookCover.midnight;
  InkPageFormat _format = InkPageFormat.a4Portrait;
  InkPageBackground _background = InkPageBackground.blank;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formats = <InkPageFormat>[
      InkPageFormat.a4Portrait,
      InkPageFormat.a4Landscape,
      InkPageFormat.a3Portrait,
      InkPageFormat.a3Landscape,
      InkPageFormat.infinite,
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Novo caderno',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome do caderno',
                  hintText: 'Ex.: Direito Constitucional',
                ),
              ),
              const SizedBox(height: 22),
              Text('Capa', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              SizedBox(
                height: 154,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: InkNotebookCover.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final cover = InkNotebookCover.values[index];
                    return SizedBox(
                      width: 112,
                      child: NotebookCoverCard(
                        cover: cover,
                        title: '',
                        selected: cover == _cover,
                        onTap: () => setState(() => _cover = cover),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              Text('Tamanho da folha',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final format in formats)
                    ChoiceChip(
                      selected: _format == format,
                      label: Text(format.label),
                      onSelected: (_) => setState(() => _format = format),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text('Papel', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: InkPageBackground.values.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  childAspectRatio: 1.12,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final background = InkPageBackground.values[index];
                  final selected = background == _background;
                  return InkWell(
                    onTap: () => setState(() => _background = background),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: NotebookPageBackground(
                              background: background,
                            ),
                          ),
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 3,
                                ),
                                child: Text(
                                  background.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF202124),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    (
                      title: _title.text.trim().isEmpty
                          ? 'Novo caderno'
                          : _title.text.trim(),
                      cover: _cover,
                      format: _format,
                      background: _background,
                    ),
                  ),
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('Criar e escrever'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPickerSheet extends StatelessWidget {
  const _CoverPickerSheet({required this.selected});

  final InkNotebookCover selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Escolher capa',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
                itemCount: InkNotebookCover.values.length,
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 210,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  final cover = InkNotebookCover.values[index];
                  return NotebookCoverCard(
                    cover: cover,
                    title: '',
                    selected: cover == selected,
                    onTap: () => Navigator.of(context).pop(cover),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
