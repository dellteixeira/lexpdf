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

enum _ShellSection { library, recent, favorites, notebooks, offline, cloud }
enum _MoreAction { allTools, account, print }

class MinimalLibrarySectionsScreen extends StatefulWidget {
  const MinimalLibrarySectionsScreen({
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
  State<MinimalLibrarySectionsScreen> createState() =>
      _MinimalLibrarySectionsScreenState();
}

class _MinimalLibrarySectionsScreenState
    extends State<MinimalLibrarySectionsScreen> {
  static const _items = <(_ShellSection, IconData, String)>[
    (_ShellSection.library, Icons.folder_outlined, 'Biblioteca'),
    (_ShellSection.recent, Icons.history, 'Recentes'),
    (_ShellSection.favorites, Icons.star_border, 'Favoritos'),
    (_ShellSection.notebooks, Icons.edit_note_outlined, 'Cadernos'),
    (_ShellSection.offline, Icons.offline_pin_outlined, 'Offline'),
    (_ShellSection.cloud, Icons.cloud_outlined, 'Nuvem'),
  ];

  final DocumentPickerService _picker = const DocumentPickerService();
  _ShellSection _section = _ShellSection.library;
  bool _opening = false;

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
            Icon(Icons.picture_as_pdf_outlined,
                color: scheme.primary, size: 22),
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
            onPressed: _opening ? null : _openPdf,
            icon: _opening
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
          PopupMenuButton<_MoreAction>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMore,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MoreAction.allTools,
                child: _MenuLabel(
                  icon: Icons.grid_view_outlined,
                  label: 'Todas as ferramentas',
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _MoreAction.account,
                child: _MenuLabel(icon: Icons.person_outline, label: 'Conta'),
              ),
              PopupMenuItem(
                value: _MoreAction.print,
                child: _MenuLabel(
                  icon: Icons.print_outlined,
                  label: 'Imprimir PDF',
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: _NavigationList(
                  section: _section,
                  onSelect: _select,
                  mobile: true,
                ),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            SizedBox(
              width: 204,
              child: _NavigationList(
                section: _section,
                onSelect: _select,
                mobile: false,
              ),
            ),
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
    if (_section == _ShellSection.notebooks) {
      return _ActionPanel(
        icon: Icons.edit_note_outlined,
        title: 'Cadernos',
        subtitle: 'Escrita, desenhos, formas, texto e imagens.',
        action: 'Abrir cadernos',
        onTap: _openNotebook,
      );
    }
    if (_section == _ShellSection.cloud) {
      return _ActionPanel(
        icon: Icons.cloud_outlined,
        title: 'Nuvem e sincronização',
        subtitle: 'Contas, arquivos remotos, fila offline e conflitos.',
        action: 'Abrir nuvem',
        onTap: _openCloud,
      );
    }
    return _documentList(_documents());
  }

  Future<List<DocumentRef>> _documents() async {
    switch (_section) {
      case _ShellSection.library:
        return widget.catalog.list(limit: 200);
      case _ShellSection.recent:
        return widget.catalog.listRecent(limit: 200);
      case _ShellSection.favorites:
        return widget.catalog.listFavorites(limit: 200);
      case _ShellSection.offline:
        final documents = await widget.catalog.list(limit: 500);
        return documents
            .where((document) => document.availableOffline)
            .toList(growable: false);
      case _ShellSection.notebooks:
      case _ShellSection.cloud:
        return const [];
    }
  }

  Widget _documentList(Future<List<DocumentRef>> future) {
    return FutureBuilder<List<DocumentRef>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final documents = snapshot.data ?? const <DocumentRef>[];
        if (documents.isEmpty) {
          return _EmptyState(
            section: _section,
            onOpen: _section == _ShellSection.library ? _openPdf : null,
          );
        }
        return ListView.separated(
          itemCount: documents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final document = documents[index];
            return _DocumentRow(
              document: document,
              onOpen: () => _openDocument(document),
              onFavorite: () => _toggleFavorite(document),
            );
          },
        );
      },
    );
  }

  void _select(_ShellSection section) {
    if (_section != section) setState(() => _section = section);
    if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openPdf() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final picked = await _picker.pickPdf();
      if (picked == null) return;
      await widget.catalog.upsert(picked);
      final stored = await widget.catalog.getById(picked.id) ?? picked;
      if (!mounted) return;
      await _openDocument(stored);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
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

  void _handleMore(_MoreAction action) {
    switch (action) {
      case _MoreAction.allTools:
        _openAllTools();
        break;
      case _MoreAction.account:
        widget.onOpenAccount();
        break;
      case _MoreAction.print:
        widget.onOpenPrint();
        break;
    }
  }
}

class _NavigationList extends StatelessWidget {
  const _NavigationList({
    required this.section,
    required this.onSelect,
    required this.mobile,
  });

  final _ShellSection section;
  final ValueChanged<_ShellSection> onSelect;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(12, mobile ? 18 : 20, 12, 12),
      children: [
        if (mobile)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Text(
              'LexPDF',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        for (final item in _MinimalLibrarySectionsScreenState._items)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: ListTile(
              dense: !mobile,
              selected: section == item.$1,
              selectedTileColor:
                  Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(item.$2, size: mobile ? 22 : 20),
              title: Text(item.$3),
              onTap: () => onSelect(item.$1),
            ),
          ),
        if (!mobile) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Icon(
                  Icons.offline_bolt_outlined,
                  size: 17,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Offline-first',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});
  final _ShellSection section;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      _ShellSection.library => 'Biblioteca',
      _ShellSection.recent => 'Recentes',
      _ShellSection.favorites => 'Favoritos',
      _ShellSection.notebooks => 'Cadernos',
      _ShellSection.offline => 'Offline',
      _ShellSection.cloud => 'Nuvem',
    };
    final subtitle = switch (section) {
      _ShellSection.library => 'Seus documentos, sem distrações.',
      _ShellSection.recent => 'Documentos realmente abertos por você.',
      _ShellSection.favorites => 'Documentos mantidos por perto.',
      _ShellSection.notebooks => 'Notas manuscritas e conteúdo livre.',
      _ShellSection.offline => 'Disponíveis sem conexão.',
      _ShellSection.cloud => 'Arquivos remotos e sincronização opcional.',
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
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.8),
        ),
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
          child: Icon(
            Icons.picture_as_pdf_outlined,
            color: scheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
                TextButton(onPressed: onTap, child: Text(action)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.section, required this.onOpen});
  final _ShellSection section;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 38,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text('Nada por aqui ainda',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              section == _ShellSection.recent
                  ? 'Abra um documento e ele aparecerá em Recentes.'
                  : 'Os documentos desta seção aparecerão aqui.',
              textAlign: TextAlign.center,
            ),
            if (onOpen != null) ...[
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
