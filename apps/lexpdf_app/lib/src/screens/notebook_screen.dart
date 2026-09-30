import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_paper.dart';
import '../core/storage/local_ink_store.dart';
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
  bool _loading = true;

  static const _templates = <(InkPageBackground, String, IconData)>[
    (InkPageBackground.blank, 'Em branco', Icons.crop_portrait_outlined),
    (InkPageBackground.ruled, 'Pautado', Icons.notes_outlined),
    (InkPageBackground.grid, 'Quadriculado', Icons.grid_4x4),
    (InkPageBackground.dotted, 'Pontilhado', Icons.blur_on),
    (InkPageBackground.cornell, 'Cornell', Icons.view_sidebar_outlined),
    (InkPageBackground.planner, 'Planner', Icons.calendar_view_week_outlined),
    (InkPageBackground.taskList, 'Lista de tarefas', Icons.check_box_outlined),
    (InkPageBackground.music, 'Partitura', Icons.music_note_outlined),
    (InkPageBackground.isometric, 'Isométrico', Icons.hexagon_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final notebooks = await widget.inkStore.listNotebooks();
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _loading = false;
    });
  }

  Future<void> _createNotebook() async {
    final result = await showModalBottomSheet<_NotebookCreation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewNotebookSheet(),
    );
    if (result == null) return;

    final notebook = await widget.inkStore.createNotebookConfigured(
      result.title,
      background: result.background,
      width: result.paper.width,
      height: result.paper.height,
    );
    if (!mounted) return;
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

  Future<void> _open(InkNotebook notebook) async {
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

  Future<void> _rename(InkNotebook notebook) async {
    final controller = TextEditingController(text: notebook.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear caderno'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await widget.inkStore.renameNotebook(notebook.id, value);
    await _reload();
  }

  Future<void> _delete(InkNotebook notebook) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir caderno?'),
            content: Text('“${notebook.title}” e todas as páginas serão removidos.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadernos'),
        actions: [
          IconButton(
            tooltip: 'Novo caderno',
            onPressed: _createNotebook,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNotebook,
        icon: const Icon(Icons.add),
        label: const Text('Novo caderno'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notebooks.isEmpty
              ? _EmptyNotebookState(onCreate: _createNotebook)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1100
                        ? 4
                        : constraints.maxWidth >= 760
                            ? 3
                            : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: 0.78,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: _notebooks.length,
                      itemBuilder: (context, index) {
                        final notebook = _notebooks[index];
                        return _NotebookCard(
                          notebook: notebook,
                          scheme: scheme,
                          onTap: () => _open(notebook),
                          onRename: () => _rename(notebook),
                          onDelete: () => _delete(notebook),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    required this.notebook,
    required this.scheme,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final InkNotebook notebook;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primaryContainer,
                      scheme.surfaceContainerHighest,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.menu_book_rounded,
                        size: 64,
                        color: scheme.primary.withValues(alpha: 0.72),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 4,
                      child: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') onRename();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Renomear')),
                          PopupMenuItem(value: 'delete', child: Text('Excluir')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toque para escrever',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.draw_outlined, size: 58),
            const SizedBox(height: 16),
            Text(
              'Seu espaço de escrita à mão',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Crie cadernos A4, A3 ou infinitos com papel pautado, quadriculado, Cornell, planner e outros.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Criar primeiro caderno'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotebookCreation {
  const _NotebookCreation({
    required this.title,
    required this.background,
    required this.paper,
  });

  final String title;
  final InkPageBackground background;
  final NotebookPaperPreset paper;
}

class _NewNotebookSheet extends StatefulWidget {
  const _NewNotebookSheet();

  @override
  State<_NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<_NewNotebookSheet> {
  final _title = TextEditingController(text: 'Novo caderno');
  InkPageBackground _background = InkPageBackground.blank;
  NotebookPaperSize _size = NotebookPaperSize.a4;
  bool _landscape = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templates = _NotebookScreenState._templates;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Novo caderno', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Nome do caderno',
                  prefixIcon: Icon(Icons.menu_book_outlined),
                ),
              ),
              const SizedBox(height: 18),
              Text('Papel', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final size in NotebookPaperSize.values)
                    ChoiceChip(
                      label: Text(size.label),
                      selected: _size == size,
                      onSelected: (_) => setState(() {
                        _size = size;
                        if (size.isInfinite) _landscape = false;
                      }),
                    ),
                ],
              ),
              if (!_size.isInfinite && _size != NotebookPaperSize.square) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Retrato')),
                    ButtonSegment(value: true, label: Text('Paisagem')),
                  ],
                  selected: {_landscape},
                  onSelectionChanged: (value) {
                    setState(() => _landscape = value.first);
                  },
                ),
              ],
              const SizedBox(height: 20),
              Text('Modelo da folha', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: templates.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.05,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (_, index) {
                  final item = templates[index];
                  final selected = _background == item.$1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _background = item.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.$3),
                          const SizedBox(height: 8),
                          Text(
                            item.$2,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    _NotebookCreation(
                      title: _title.text.trim(),
                      background: _background,
                      paper: NotebookPaperPreset(
                        size: _size,
                        landscape: _landscape,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Criar e começar a escrever'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
