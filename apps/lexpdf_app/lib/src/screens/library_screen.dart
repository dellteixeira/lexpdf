import 'dart:io';

import 'package:flutter/material.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'backup_migration_screen.dart';
import 'cloud_sync_screen.dart';
import 'global_search_screen.dart';
import 'library_organizer_screen.dart';
import 'notebook_export_screen.dart';
import 'notebook_screen.dart';
import 'pdf_advanced_annotation_screen.dart';
import 'pdf_navigation_screen.dart';
import 'pdf_ocr_screen.dart';
import 'pdf_page_tools_screen.dart';
import 'pdf_workspace_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.catalog,
    required this.readingProgress,
    required this.annotations,
    required this.inkStore,
    required this.pdfInkStore,
    super.key,
  });

  final LocalDocumentCatalog catalog;
  final LocalReadingProgressStore readingProgress;
  final LocalTextAnnotationStore annotations;
  final LocalInkStore inkStore;
  final LocalPdfInkStore pdfInkStore;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedIndex = 0;
  bool _openingDocument = false;
  final DocumentPickerService _picker = const DocumentPickerService();

  LocalPdfNavigationStore get _navigationStore =>
      LocalPdfNavigationStore(widget.annotations.db);

  static const _destinations = <(IconData, String)>[
    (Icons.folder_outlined, 'Biblioteca'),
    (Icons.history, 'Recentes'),
    (Icons.star_border, 'Favoritos'),
    (Icons.edit_note, 'Cadernos'),
    (Icons.offline_pin_outlined, 'Offline'),
    (Icons.cloud_outlined, 'Nuvens'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined),
            SizedBox(width: 10),
            Text('LexPDF'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Busca local',
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Nuvem e sincronização',
            onPressed: _openCloudSync,
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: 'Abrir PDF',
            onPressed: _openingDocument ? null : _openPdf,
            icon: _openingDocument
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_open_outlined),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(Icons.offline_bolt_outlined, size: 18),
              label: Text('Offline-first'),
            ),
          ),
        ],
      ),
      drawer: compact
          ? Drawer(
              child: _Navigation(
                selectedIndex: _selectedIndex,
                onSelect: _select,
              ),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            SizedBox(
              width: 232,
              child: _Navigation(
                selectedIndex: _selectedIndex,
                onSelect: _select,
              ),
            ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _destinations[_selectedIndex].$2,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seus PDFs e cadernos permanecem disponíveis localmente. A sincronização é opcional.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Expanded(child: _buildSection()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection() {
    if (_selectedIndex == 1) {
      return _buildDocumentList(
        future: widget.catalog.list(limit: 100),
        emptyIcon: Icons.history,
        emptyTitle: 'Nenhum PDF recente',
        emptySubtitle: 'Os documentos abertos aparecerão aqui automaticamente.',
      );
    }

    if (_selectedIndex == 2) {
      return _buildDocumentList(
        future: widget.catalog.listFavorites(limit: 100),
        emptyIcon: Icons.star_border,
        emptyTitle: 'Nenhum favorito',
        emptySubtitle: 'Toque na estrela de um documento para mantê-lo aqui.',
      );
    }

    if (_selectedIndex == 3) {
      return GridView.extent(
        maxCrossAxisExtent: 320,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          _QuickAction(
            icon: Icons.edit_outlined,
            title: 'Abrir cadernos',
            subtitle: 'Páginas, escrita, formas, texto e imagens',
            onTap: _openNotebook,
          ),
          _QuickAction(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Exportar caderno',
            subtitle: 'Página atual ou caderno completo em PDF',
            onTap: _openNotebookExport,
          ),
        ],
      );
    }

    if (_selectedIndex == 4) {
      return _buildDocumentList(
        future: _offlineDocuments(),
        emptyIcon: Icons.offline_pin_outlined,
        emptyTitle: 'Nenhum documento em cache offline',
        emptySubtitle: 'Downloads da nuvem aparecerão aqui automaticamente.',
      );
    }

    if (_selectedIndex == 5) {
      return GridView.extent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          _QuickAction(
            icon: Icons.cloud_sync_outlined,
            title: 'Contas e sincronização',
            subtitle: 'Google Drive, OneDrive, iCloud e LexPDF Cloud/R2',
            onTap: _openCloudSync,
          ),
          _QuickAction(
            icon: Icons.backup_outlined,
            title: 'Backup e migração',
            subtitle: '.lexbackup, .lexnote e importação Squid segura',
            onTap: _openBackupMigration,
          ),
        ],
      );
    }

    return GridView.extent(
      maxCrossAxisExtent: 360,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _PdfWorkspaceAction(
          loading: _openingDocument,
          onTap: _openingDocument ? null : _openPdf,
        ),
        _QuickAction(
          icon: Icons.manage_search_outlined,
          title: 'Busca local',
          subtitle: 'PDFs, anotações, OCR e cadernos',
          onTap: _openSearch,
        ),
        _QuickAction(
          icon: Icons.folder_copy_outlined,
          title: 'Organizar biblioteca',
          subtitle: 'Coleções e tags offline',
          onTap: _openOrganizer,
        ),
        _QuickAction(
          icon: Icons.note_add_outlined,
          title: 'Novo caderno',
          subtitle: 'Escrita e desenhos',
          onTap: _openNotebook,
        ),
        _QuickAction(
          icon: Icons.cloud_outlined,
          title: 'Conectar nuvem',
          subtitle: 'Google Drive, OneDrive, iCloud ou R2',
          onTap: _openCloudSync,
        ),
        _QuickAction(
          icon: Icons.backup_outlined,
          title: 'Backup',
          subtitle: 'Criar, validar, restaurar ou migrar',
          onTap: _openBackupMigration,
        ),
      ],
    );
  }

  Future<List<DocumentRef>> _offlineDocuments() async {
    final documents = await widget.catalog.list(limit: 500);
    return documents
        .where((document) => document.availableOffline)
        .toList(growable: false);
  }

  Widget _buildDocumentList({
    required Future<List<DocumentRef>> future,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    return FutureBuilder<List<DocumentRef>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data ?? const <DocumentRef>[];
        if (documents.isEmpty) {
          return _EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle,
          );
        }

        return ListView.separated(
          itemCount: documents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final document = documents[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(
                  document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  document.availableOffline
                      ? 'Disponível offline'
                      : 'Necessita download',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Navegação avançada',
                      icon: const Icon(Icons.navigation_outlined),
                      onPressed: document.availableOffline
                          ? () => _openNavigationDocument(document)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Anotações avançadas',
                      icon: const Icon(Icons.draw_outlined),
                      onPressed: document.availableOffline
                          ? () => _openAdvancedDocument(document)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Editar páginas',
                      icon: const Icon(Icons.edit_document),
                      onPressed: document.availableOffline
                          ? () => _openPageToolsDocument(document)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'OCR offline',
                      icon: const Icon(Icons.document_scanner_outlined),
                      onPressed: document.availableOffline
                          ? () => _openOcrDocument(document)
                          : null,
                    ),
                    IconButton(
                      tooltip: document.favorite
                          ? 'Remover dos favoritos'
                          : 'Adicionar aos favoritos',
                      icon: Icon(
                        document.favorite ? Icons.star : Icons.star_border,
                      ),
                      onPressed: () => _toggleFavorite(document),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: document.availableOffline
                    ? () => _openDocument(document)
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleFavorite(DocumentRef document) async {
    await widget.catalog.setFavorite(document.id, !document.favorite);
    if (mounted) setState(() {});
  }

  Future<DocumentRef?> _pickAndStorePdf() async {
    final document = await _picker.pickPdf();
    if (!mounted || document == null) return null;

    final path = document.localPath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      throw StateError('O arquivo selecionado não está acessível neste dispositivo.');
    }

    await widget.catalog.upsert(document);
    return await widget.catalog.getById(document.id) ?? document;
  }

  Future<void> _openPdf() async {
    if (_openingDocument) return;
    setState(() => _openingDocument = true);

    try {
      final stored = await _pickAndStorePdf();
      if (stored != null) {
        await _openDocument(stored);
      }
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
    await widget.catalog.markOpened(document.id);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfWorkspaceScreen(
          document: document,
          readingProgress: widget.readingProgress,
          annotations: widget.annotations,
          pdfInkStore: widget.pdfInkStore,
        ),
      ),
    );

    if (mounted) setState(() {});
  }

  Future<void> _openNavigationDocument(DocumentRef document) async {
    await widget.catalog.markOpened(document.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfNavigationScreen(
          document: document,
          store: _navigationStore,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openAdvancedDocument(DocumentRef document) async {
    await widget.catalog.markOpened(document.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfAdvancedAnnotationScreen(
          document: document,
          annotations: widget.annotations,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openPageToolsDocument(DocumentRef document) async {
    await widget.catalog.markOpened(document.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPageToolsScreen(document: document),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openOcrDocument(DocumentRef document) async {
    await widget.catalog.markOpened(document.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfOcrScreen(
          document: document,
          navigationStore: _navigationStore,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GlobalSearchScreen(
          catalog: widget.catalog,
          store: _navigationStore,
        ),
      ),
    );
  }

  Future<void> _openOrganizer() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryOrganizerScreen(
          catalog: widget.catalog,
          store: _navigationStore,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openCloudSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSyncScreen(db: widget.annotations.db),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openBackupMigration() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupMigrationScreen(db: widget.annotations.db),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openNotebook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotebookScreen(inkStore: widget.inkStore),
      ),
    );
  }

  Future<void> _openNotebookExport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotebookExportScreen(inkStore: widget.inkStore),
      ),
    );
  }

  void _select(int index) => setState(() => _selectedIndex = index);
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: NavigationDrawer(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 18, 16, 10),
            child: Text('DOCUMENTOS'),
          ),
          for (final destination in _LibraryScreenState._destinations)
            NavigationDrawerDestination(
              icon: Icon(destination.$1),
              label: Text(destination.$2),
            ),
        ],
      ),
    );
  }
}

class _PdfWorkspaceAction extends StatelessWidget {
  const _PdfWorkspaceAction({
    required this.loading,
    this.onTap,
  });

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  loading
                      ? const SizedBox.square(
                          dimension: 36,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 42),
                  const Spacer(),
                  const Icon(Icons.arrow_forward),
                ],
              ),
              const Spacer(),
              Text(
                'Abrir e trabalhar com PDF',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Abra uma única vez e use a mesma guia para ler, navegar, anotar, editar páginas e executar OCR.',
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FeatureChip(icon: Icons.menu_book_outlined, label: 'Ler'),
                  _FeatureChip(icon: Icons.navigation_outlined, label: 'Navegar'),
                  _FeatureChip(icon: Icons.draw_outlined, label: 'Anotar'),
                  _FeatureChip(icon: Icons.edit_document, label: 'Páginas'),
                  _FeatureChip(
                    icon: Icons.document_scanner_outlined,
                    label: 'OCR',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(icon, size: 42),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
