import 'package:flutter/material.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'notebook_export_screen.dart';
import 'notebook_screen.dart';
import 'pdf_reader_screen.dart';

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
          IconButton(tooltip: 'Buscar', onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(
            tooltip: 'Abrir arquivo',
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
              label: Text('Offline'),
            ),
          ),
        ],
      ),
      drawer: compact
          ? Drawer(
              child: _Navigation(selectedIndex: _selectedIndex, onSelect: _select),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            SizedBox(
              width: 232,
              child: _Navigation(selectedIndex: _selectedIndex, onSelect: _select),
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
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
    if (_selectedIndex != 0) {
      return const _EmptyState(
        icon: Icons.construction_outlined,
        title: 'Módulo em construção',
        subtitle: 'Esta área já está reservada na arquitetura do LexPDF.',
      );
    }
    return GridView.extent(
      maxCrossAxisExtent: 280,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _QuickAction(
          icon: Icons.file_open_outlined,
          title: 'Abrir PDF',
          subtitle: 'Neste dispositivo',
          onTap: _openingDocument ? null : _openPdf,
        ),
        _QuickAction(
          icon: Icons.note_add_outlined,
          title: 'Novo caderno',
          subtitle: 'Escrita e desenhos',
          onTap: _openNotebook,
        ),
        const _QuickAction(icon: Icons.cloud_outlined, title: 'Conectar nuvem', subtitle: 'Google, OneDrive ou iCloud'),
        const _QuickAction(icon: Icons.backup_outlined, title: 'Backup', subtitle: 'Local ou em nuvem'),
      ],
    );
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
          return _EmptyState(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle);
        }
        return ListView.separated(
          itemCount: documents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final document = documents[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(document.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(document.availableOffline ? 'Disponível offline' : 'Necessita download'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: document.favorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
                      icon: Icon(document.favorite ? Icons.star : Icons.star_border),
                      onPressed: () => _toggleFavorite(document),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: document.availableOffline ? () => _openDocument(document) : null,
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

  Future<void> _openPdf() async {
    if (_openingDocument) return;
    setState(() => _openingDocument = true);
    try {
      final document = await _picker.pickPdf();
      if (!mounted || document == null) return;
      await widget.catalog.upsert(document);
      final stored = await widget.catalog.getById(document.id) ?? document;
      await _openDocument(stored);
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
  const _Navigation({required this.selectedIndex, required this.onSelect});
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
            NavigationDrawerDestination(icon: Icon(destination.$1), label: Text(destination.$2)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.title, required this.subtitle, this.onTap});
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
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
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
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
