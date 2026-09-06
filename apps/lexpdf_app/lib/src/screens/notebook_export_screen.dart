import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_pdf_exporter.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_notebook_object_store.dart';

class NotebookExportScreen extends StatefulWidget {
  const NotebookExportScreen({required this.inkStore, super.key});

  final LocalInkStore inkStore;

  @override
  State<NotebookExportScreen> createState() => _NotebookExportScreenState();
}

class _NotebookExportScreenState extends State<NotebookExportScreen> {
  static const NotebookPdfExporter _exporter = NotebookPdfExporter();

  late final LocalNotebookObjectStore _objectStore;
  late Future<void> _loadFuture;
  List<InkNotebook> _notebooks = const [];
  List<InkNotebookPage> _pages = const [];
  InkNotebook? _selectedNotebook;
  InkNotebookPage? _selectedPage;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _objectStore = LocalNotebookObjectStore(widget.inkStore.db);
    _loadFuture = _load();
  }

  Future<void> _load() async {
    await widget.inkStore.ensureDefaultPage();
    final notebooks = await widget.inkStore.listNotebooks();
    if (notebooks.isEmpty) return;
    final selected = notebooks.first;
    final pages = await widget.inkStore.listPages(selected.id);
    _notebooks = notebooks;
    _selectedNotebook = selected;
    _pages = pages;
    _selectedPage = pages.isEmpty ? null : pages.first;
  }

  Future<void> _selectNotebook(String id) async {
    final notebook = _notebooks.firstWhere((item) => item.id == id);
    final pages = await widget.inkStore.listPages(id);
    if (!mounted) return;
    setState(() {
      _selectedNotebook = notebook;
      _pages = pages;
      _selectedPage = pages.isEmpty ? null : pages.first;
    });
  }

  Future<List<NotebookExportPageData>> _collectPages(
    List<InkNotebookPage> pages,
  ) async {
    final result = <NotebookExportPageData>[];
    for (final page in pages) {
      result.add(
        NotebookExportPageData(
          page: page,
          strokes: await widget.inkStore.listStrokes(page.id),
          objects: await _objectStore.listObjects(page.id),
        ),
      );
    }
    return result;
  }

  Future<void> _exportPage() async {
    final notebook = _selectedNotebook;
    final page = _selectedPage;
    if (notebook == null || page == null) return;
    await _performExport(
      title: '${notebook.title} — página ${page.pageNumber}',
      fileName: '${_safeName(notebook.title)}_pagina_${page.pageNumber}.pdf',
      pages: [page],
    );
  }

  Future<void> _exportNotebook() async {
    final notebook = _selectedNotebook;
    if (notebook == null || _pages.isEmpty) return;
    await _performExport(
      title: notebook.title,
      fileName: '${_safeName(notebook.title)}.pdf',
      pages: _pages,
    );
  }

  Future<void> _performExport({
    required String title,
    required String fileName,
    required List<InkNotebookPage> pages,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final data = await _collectPages(pages);
      final bytes = await _exporter.export(title: title, pages: data);
      final path = await _savePdf(bytes, fileName);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF salvo em: $path')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível exportar o caderno: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<String?> _savePdf(Uint8List bytes, String fileName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(suggestedName: fileName);
      if (location == null) return null;
      await XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: fileName,
      ).saveTo(location.path);
      return location.path;
    }

    final documents = await getApplicationDocumentsDirectory();
    final exports = Directory(
      '${documents.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}exports',
    );
    await exports.create(recursive: true);
    final path = '${exports.path}${Platform.pathSeparator}$fileName';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  String _safeName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return normalized.isEmpty ? 'caderno' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar caderno')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Não foi possível carregar os cadernos: ${snapshot.error}'),
            );
          }
          if (_notebooks.isEmpty) {
            return const Center(child: Text('Nenhum caderno disponível.'));
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Exportação PDF',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Traços e formas são exportados como conteúdo vetorial. Imagens inseridas permanecem rasterizadas.',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _selectedNotebook?.id,
                decoration: const InputDecoration(
                  labelText: 'Caderno',
                  border: OutlineInputBorder(),
                ),
                items: _notebooks
                    .map(
                      (notebook) => DropdownMenuItem(
                        value: notebook.id,
                        child: Text(notebook.title),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _exporting
                    ? null
                    : (id) {
                        if (id != null) _selectNotebook(id);
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedPage?.id,
                decoration: const InputDecoration(
                  labelText: 'Página',
                  border: OutlineInputBorder(),
                ),
                items: _pages
                    .map(
                      (page) => DropdownMenuItem(
                        value: page.id,
                        child: Text('Página ${page.pageNumber}'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _exporting
                    ? null
                    : (id) {
                        if (id == null) return;
                        setState(() {
                          _selectedPage = _pages.firstWhere((page) => page.id == id);
                        });
                      },
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _exporting || _selectedPage == null ? null : _exportPage,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Exportar página'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exporting || _pages.isEmpty ? null : _exportNotebook,
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text('Exportar caderno (${_pages.length} páginas)'),
                  ),
                ],
              ),
              if (_exporting) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}
