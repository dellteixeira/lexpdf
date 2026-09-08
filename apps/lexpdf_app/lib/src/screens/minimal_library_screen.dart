import 'package:flutter/material.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'cloud_sync_screen.dart';
import 'global_search_screen.dart';
import 'library_screen.dart';
import 'notebook_screen.dart';
import 'pdf_reader_screen.dart';

enum _LibrarySection { library, recent, favorites, notebooks, offline }

enum _LibraryMoreAction { cloud, allTools, account, print }

class MinimalLibraryScreen extends StatefulWidget {
  const MinimalLibraryScreen({
    required this.catalog,
    required this.readingProgress,
    required this.annotations,
    required this.inkStore,
    required this.pdfInkStore,
    required this.onOpenAccount,
    required this.onOpenPrint,
    super.key,
  });

  final LocalDocumentCatalog catalog;
  final LocalReadingProgressStore readingProgress;
  final LocalTextAnnotationStore annotations;
  final LocalInkStore inkStore;
  final LocalPdfInkStore pdfInkStore;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenPrint;

  @override
  State<MinimalLibraryScreen> createState() => _MinimalLibraryScreenState();
}

class _MinimalLibraryScreenState extends State<MinimalLibraryScreen> {
  static const _sections = <(_LibrarySection, IconData, String)>[
    (_LibrarySection.library, Icons.folder_outlined, 'Biblioteca'),
    (_LibrarySection.recent, Icons.history, 'Recentes'),
    (_LibrarySection.favorites, Icons.star_border, 'Favoritos'),
    (_LibrarySection.notebooks, Icons.edit_note_outlined, 'Cadernos'),
    (_LibrarySection.offline, Icons.offline_pin_outlined, 'Offline'),
  ];

  final DocumentPickerService _picker = const DocumentPickerService();
  _LibrarySection _section = _LibrarySection.library;
  bool _openingDocument = false;

  LocalPdfNavigationStore get _navigationStore =>
      LocalPdfNavigationStore(widget.annotations.db);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: compact
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              )
            : null,
        automaticallyImplyLeading: false,
        titleSpacing: compact ? 0 : 24,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, color: scheme.primary, size: 22),
            const SizedBox(width: 9),
            const Text('LexPDF'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Abrir PDF',
            onPressed: _openingDocument ? null : _openPdf,
            icon: _openingDocument
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
          PopupMenuButton<_LibraryMoreAction>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMore,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _LibraryMoreAction.cloud,
                child: _MenuLabel(icon: Icons.cloud_outlined, label: 'Nuvem e sincronização'),
              ),
              PopupMenuItem(
                value: _LibraryMoreAction.allTools,
                child: _MenuLabel(icon: Icons.grid_view_outlined, label: 'Todas as ferramentas'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _LibraryMoreAction.account,
                child: _MenuLabel(icon: Icons.person_outline, label: 'Conta'),
              ),
              PopupMenuItem(
                value: _LibraryMoreAction.print,
                child: _MenuLabel(icon: Icons.print_outlined, label: 'Imprimir PDF'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: compact
          ? Drawer(
              child: SafeArea(child: _MobileNavigation(section: _section, onSelect: _select)),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            _DesktopNavigation(section: _section, onSelect: _select),
          if (!compact) const VerticalDivider(width: 1),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 18 : 32,
                    compact ? 22 : 30,
                    compact ? 18 : 32,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(section: _section),
                      const SizedBox(height: 22),
                      Expanded(child: _buildContent()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_section == _LibrarySection.notebooks) {
      return Align(
        alignment: Alignment.topLeft,
        child: _MinimalActionCard(
          icon: Icons.edit_note_outlined,
          title: 'Cadernos',
          subtitle: 'Escrita, desenhos, formas, texto e imagens.',
          actionLabel: 'Abrir',
          onTap: _openNotebook,
        ),
      );
    }

    return _buildDocumentList(_documentsForSection());
  }

  Future<List<DocumentRef>> _documentsForSection() async {
    switch (_section) {
      case _LibrarySection.library:
      case _LibrarySection.recent:
        return widget.catalog.list(limit: 200);
      case _LibrarySection.favorites:
        return widget.catalog.listFavorites(limit: 200);
      case _LibrarySection.offline:
        final documents = await widget.catalog.list(limit: 500);
        return documents.where((item) => item.availableOffline).toList(growable: false);
      case _LibrarySection.notebooks:
        return const [];
    }
  }

  Widget _buildDocumentList(Future<List<DocumentRef>> future) {
    return FutureBuilder<List<DocumentRef>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final documents = snapshot.data ?? const <DocumentRef>[];
        if (documents.isEmpty) return _EmptyLibrary(section: _section, onOpen: _openPdf);

        return ListView.separated(
          itemCount: documents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _DocumentRow(
            document: documents[index],
            onOpen: () => _openDocument(documents[index]),
            onFavorite: () => _toggleFavorite(documents[index]),
          ),
        );
      },
    );
  }

  void _select(_LibrarySection section) {
    if (_section == section) return;
    setState(() => _section = section);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _openPdf() async {
    if (_openingDocument) return;
    setState(() => _openingDocument = true);
    try {
      final picked = await _picker.pickPdf();
      if (picked == null) return;
      await widget.catalog.upsert(picked);
      final stored = await widget.catalog.getById(picked.id) ?? picked;
      if (!mounted) return;
      await _openDocument(stored);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _openingDocument = false);
    }
  }

  Future<void> _openDocument(DocumentRef document) async {
    if (!document.availableOffline) return;
    await widget.catalog.markOpened(document.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfReaderScreen(
          document: document,
          readingProgress: widget.readingProgress,
          annotations: widget.annotations,
          pdfInkStore: widget.pdfInkStore,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(DocumentRef document) async {
    await widget.catalog.setFavorite(document.id, !document.favorite);
    if (mounted) setState(() {});
  }

  Future<void> _openSearch() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GlobalSearchScreen(
            catalog: widget.catalog,
            store: _navigationStore,
          ),
        ),
      );

  Future<void> _openCloud() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CloudSyncScreen(db: widget.annotations.db),
        ),
      );

  Future<void> _openNotebook() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotebookScreen(inkStore: widget.inkStore),
        ),
      );

  Future<void> _openAllTools() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LibraryScreen(
            catalog: widget.catalog,
            readingProgress: widget.readingProgress,
            annotations: widget.annotations,
            inkStore: widget.inkStore,
            pdfInkStore: widget.pdfInkStore,
          ),
        ),
      );

  void _handleMore(_LibraryMoreAction action) {
    switch (action) {
      case _LibraryMoreAction.cloud:
        _openCloud();
        break;
      case _LibraryMoreAction.allTools:
        _openAllTools();
        break;
      case _LibraryMoreAction.account:
        widget.onOpenAccount();
        break;
      case _LibraryMoreAction.print:
        widget.onOpenPrint();
        break;
    }
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({required this.section, required this.onSelect});

  final _LibrarySection section;
  final ValueChanged<_LibrarySection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 204,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        child: Column(
          children: [
            for (final item in _MinimalLibraryScreenState._sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: ListTile(
                  dense: true,
                  minLeadingWidth: 24,
                  selected: section == item.$1,
                  selectedTileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(item.$2, size: 20),
                  title: Text(item.$3),
                  onTap: () => onSelect(item.$1),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt_outlined,
                      size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline-first',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({required this.section, required this.onSelect});

  final _LibrarySection section;
  final ValueChanged<_LibrarySection> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Text('LexPDF', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        for (final item in _MinimalLibraryScreenState._sections)
          ListTile(
            selected: section == item.$1,
            selectedTileColor: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Icon(item.$2),
            title: Text(item.$3),
            onTap: () => onSelect(item.$1),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final _LibrarySection section;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      _LibrarySection.library => 'Biblioteca',
      _LibrarySection.recent => 'Recentes',
      _LibrarySection.favorites => 'Favoritos',
      _LibrarySection.notebooks => 'Cadernos',
      _LibrarySection.offline => 'Offline',
    };
    final subtitle = switch (section) {
      _LibrarySection.library => 'Seus documentos, sem distrações.',
      _LibrarySection.recent => 'Continue de onde parou.',
      _LibrarySection.favorites => 'Documentos mantidos por perto.',
      _LibrarySection.notebooks => 'Notas manuscritas e conteúdo livre.',
      _LibrarySection.offline => 'Disponíveis sem conexão.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.onOpen,
    required this.onFavorite,
  });

  final DocumentRef document;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.picture_as_pdf_outlined, color: scheme.primary, size: 20),
        ),
        title: Text(document.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          document.availableOffline ? 'Disponível offline' : 'Necessita download',
          maxLines: 1,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: document.favorite ? 'Remover favorito' : 'Favoritar',
              onPressed: onFavorite,
              icon: Icon(document.favorite ? Icons.star : Icons.star_border),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        onTap: document.availableOffline ? onOpen : null,
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.section, required this.onOpen});

  final _LibrarySection section;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isLibrary = section == _LibrarySection.library || section == _LibrarySection.recent;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 38, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('Nada por aqui ainda', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              isLibrary
                  ? 'Abra um PDF para começar sua biblioteca local.'
                  : 'Os documentos desta seção aparecerão aqui.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (isLibrary) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.add),
                label: const Text('Abrir PDF'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MinimalActionCard extends StatelessWidget {
  const _MinimalActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              TextButton(onPressed: onTap, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
