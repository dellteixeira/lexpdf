import 'dart:async';

import 'package:flutter/material.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'cloud_sync_screen.dart';
import 'global_search_screen.dart';
import 'notebook_screen.dart';
import 'pdf_workspace_screen.dart';

enum _HomeSection { library, recent, favorites, notebooks, offline, cloud }
enum _HomeMoreAction { account, print }

class LibraryWorkspaceHomeScreen extends StatefulWidget {
  const LibraryWorkspaceHomeScreen({
    required this.catalog,
    required this.annotations,
    required this.inkStore,
    required this.onOpenAccount,
    required this.onOpenPrint,
    super.key,
  });

  final LocalDocumentCatalog catalog;
  final LocalTextAnnotationStore annotations;
  final LocalInkStore inkStore;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenPrint;

  @override
  State<LibraryWorkspaceHomeScreen> createState() =>
      _LibraryWorkspaceHomeScreenState();
}

class _LibraryWorkspaceHomeScreenState extends State<LibraryWorkspaceHomeScreen> {
  static const _items = <(_HomeSection, IconData, String)>[
    (_HomeSection.library, Icons.folder_outlined, 'Biblioteca'),
    (_HomeSection.recent, Icons.history, 'Recentes'),
    (_HomeSection.favorites, Icons.star_border, 'Favoritos'),
    (_HomeSection.notebooks, Icons.edit_note_outlined, 'Cadernos'),
    (_HomeSection.offline, Icons.offline_pin_outlined, 'Offline'),
    (_HomeSection.cloud, Icons.cloud_outlined, 'Nuvem'),
  ];

  final DocumentPickerService _picker = const DocumentPickerService();
  _HomeSection _section = _HomeSection.library;
  bool _picking = false;

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
            tooltip: 'Abrir PDF em Trabalhar com PDF',
            onPressed: _picking ? null : _pickPdf,
            icon: _picking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
          PopupMenuButton<_HomeMoreAction>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMore,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeMoreAction.account,
                child: _MenuLabel(icon: Icons.person_outline, label: 'Conta'),
              ),
              PopupMenuItem(
                value: _HomeMoreAction.print,
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
                      const SizedBox(height: 12),
                      if (_section == _HomeSection.library) ...[
                        _WorkspaceHint(onOpen: _picking ? null : _pickPdf),
                        const SizedBox(height: 14),
                      ],
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
    if (_section == _HomeSection.notebooks) {
      return _ActionPanel(
        icon: Icons.edit_note_outlined,
        title: 'Cadernos',
        subtitle: 'Escrita, desenhos, formas, texto e imagens.',
        action: 'Abrir cadernos',
        onTap: _openNotebook,
      );
    }
    if (_section == _HomeSection.cloud) {
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
      case _HomeSection.library:
        return widget.catalog.list(limit: 200);
      case _HomeSection.recent:
        return widget.catalog.listRecent(limit: 200);
      case _HomeSection.favorites:
        return widget.catalog.listFavorites(limit: 200);
      case _HomeSection.offline:
        final documents = await widget.catalog.list(limit: 500);
        return documents.where((document) => document.hasLocalPath).toList(growable: false);
      case _HomeSection.notebooks:
      case _HomeSection.cloud:
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
            onOpen: _section == _HomeSection.library ? _pickPdf : null,
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

  void _select(_HomeSection section) {
    if (_section != section) setState(() => _section = section);
    if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickPdf() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickPdf();
      if (picked == null || !mounted) return;

      // Opening the workspace must never wait for catalog/database bookkeeping.
      unawaited(_rememberDocument(picked));
      await _openDocument(picked, recordOpen: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _rememberDocument(DocumentRef document) async {
    await widget.catalog.upsert(document);
    await widget.catalog.markOpened(document.id);
    if (mounted) setState(() {});
  }

  Future<void> _openDocument(
    DocumentRef document, {
    bool recordOpen = true,
  }) async {
    if (!document.hasLocalPath) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O arquivo local deste PDF não está disponível.'),
        ),
      );
      return;
    }

    if (recordOpen) {
      // Do not block the first frame of the PDF workspace on a SQLite write.
      unawaited(widget.catalog.markOpened(document.id));
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfWorkspaceScreen(
          document: document,
          store: _navigationStore,
          annotations: widget.annotations,
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

  void _handleMore(_HomeMoreAction action) {
    switch (action) {
      case _HomeMoreAction.account:
        widget.onOpenAccount();
        break;
      case _HomeMoreAction.print:
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

  final _HomeSection section;
  final ValueChanged<_HomeSection> onSelect;
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
        for (final item in _LibraryWorkspaceHomeScreenState._items)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: ListTile(
              dense: !mobile,
              selected: section == item.$1,
              selectedTileColor: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                Text('Offline-first', style: Theme.of(context).textTheme.labelMedium),
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
  final _HomeSection section;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      _HomeSection.library => 'Biblioteca',
      _HomeSection.recent => 'Recentes',
      _HomeSection.favorites => 'Favoritos',
      _HomeSection.notebooks => 'Cadernos',
      _HomeSection.offline => 'Offline',
      _HomeSection.cloud => 'Nuvem',
    };
    final subtitle = switch (section) {
      _HomeSection.library => 'Clique em um documento para abrir diretamente em Trabalhar com PDF.',
      _HomeSection.recent => 'Documentos realmente abertos por você.',
      _HomeSection.favorites => 'Documentos mantidos por perto.',
      _HomeSection.notebooks => 'Notas manuscritas e conteúdo livre.',
      _HomeSection.offline => 'Arquivos locais prontos para abrir.',
      _HomeSection.cloud => 'Arquivos remotos e sincronização opcional.',
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

class _WorkspaceHint extends StatelessWidget {
  const _WorkspaceHint({required this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.edit_document, color: scheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Os PDFs da Biblioteca abrem no espaço completo de leitura e ferramentas.'),
            ),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.add),
              label: const Text('Abrir PDF'),
            ),
          ],
        ),
      ),
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
    final canOpen = document.hasLocalPath;
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
          canOpen ? 'Abrir em Trabalhar com PDF' : 'Arquivo local indisponível',
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
        onTap: canOpen ? onOpen : null,
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
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
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
  final _HomeSection section;
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
            Text('Nada por aqui ainda', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              section == _HomeSection.recent
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
