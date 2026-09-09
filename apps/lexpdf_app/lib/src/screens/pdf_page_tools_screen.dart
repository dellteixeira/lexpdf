import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/pdf/large_pdf_manipulation_service.dart';
import '../core/pdf/pdf_page_manipulation_service.dart';
import '../core/pdf/safe_pdf_writer.dart';

class PdfPageToolsScreen extends StatefulWidget {
  const PdfPageToolsScreen({required this.document, super.key});

  final DocumentRef document;

  @override
  State<PdfPageToolsScreen> createState() => _PdfPageToolsScreenState();
}

class _PlannedPage {
  _PlannedPage({
    required this.id,
    required this.sourcePageNumber,
    this.clockwiseQuarterTurns = 0,
  });

  final String id;
  final int sourcePageNumber;
  int clockwiseQuarterTurns;
  bool selected = false;
}

class _PdfPageToolsScreenState extends State<PdfPageToolsScreen> {
  static const _service = PdfPageManipulationService();
  static const _largeService = LargePdfManipulationService();
  static const _writer = SafePdfWriter();

  final List<_PlannedPage> _pages = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  String? get _sourcePath => widget.document.localPath;

  int get _selectedCount => _pages.where((page) => page.selected).length;

  bool get _planIsIdentity {
    for (var index = 0; index < _pages.length; index++) {
      final page = _pages[index];
      if (page.sourcePageNumber != index + 1 ||
          page.clockwiseQuarterTurns % 4 != 0) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    final path = _sourcePath;
    if (path == null || path.isEmpty) {
      setState(() {
        _loading = false;
        _error = StateError('O PDF precisa estar disponível offline.');
      });
      return;
    }
    try {
      await _writer.recoverPending(path);
      final document = await PdfDocument.openFile(path);
      try {
        _pages.clear();
        for (var index = 0; index < document.pages.length; index++) {
          _pages.add(
            _PlannedPage(
              id:
                  'page-${index + 1}-${DateTime.now().microsecondsSinceEpoch}-$index',
              sourcePageNumber: index + 1,
            ),
          );
        }
      } finally {
        await document.dispose();
      }
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PdfPageSpec> _specs(Iterable<_PlannedPage> pages) {
    final source = _sourcePath!;
    return pages
        .map(
          (page) => PdfPageSpec(
            sourcePath: source,
            pageNumber: page.sourcePageNumber,
            clockwiseQuarterTurns: page.clockwiseQuarterTurns,
          ),
        )
        .toList(growable: false);
  }

  Future<String?> _chooseOutputPath(String suggestedName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(suggestedName: suggestedName);
      return location?.path;
    }
    final directory = await getApplicationDocumentsDirectory();
    final exports = Directory(
      '${directory.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}exports',
    );
    await exports.create(recursive: true);
    return '${exports.path}${Platform.pathSeparator}$suggestedName';
  }

  Future<void> _showSaved(String label, String path) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label: $path')),
    );
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operação não concluída: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T> _withCurrentPlanPath<T>(
    Future<T> Function(String path) action,
  ) async {
    final source = _sourcePath;
    if (source == null) throw StateError('PDF não disponível offline.');
    if (_planIsIdentity) return action(source);
    if (_pages.isEmpty) {
      throw StateError('O documento não pode ficar sem páginas.');
    }

    final temp = await Directory.systemTemp.createTemp('lexpdf-page-plan-');
    try {
      final path = '${temp.path}${Platform.pathSeparator}planned.pdf';
      await _largeService.composeToFile(
        _specs(_pages),
        outputPath: path,
      );
      return await action(path);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<void> _savePlan() => _run(() async {
        if (_pages.isEmpty) {
          throw StateError('O documento não pode ficar sem páginas.');
        }
        final destination = await _chooseOutputPath('lexpdf_editado.pdf');
        if (destination == null) return;
        await _largeService.composeToFile(
          _specs(_pages),
          outputPath: destination,
        );
        await _showSaved('PDF salvo', destination);
      });

  Future<void> _extractSelected() => _run(() async {
        final selected = _pages.where((page) => page.selected).toList();
        if (selected.isEmpty) {
          throw StateError('Selecione pelo menos uma página.');
        }
        final destination =
            await _chooseOutputPath('lexpdf_paginas_extraidas.pdf');
        if (destination == null) return;
        await _largeService.composeToFile(
          _specs(selected),
          outputPath: destination,
        );
        await _showSaved('Páginas extraídas', destination);
      });

  Future<void> _mergePdf() => _run(() async {
        const types = <XTypeGroup>[
          XTypeGroup(
            label: 'PDF',
            extensions: ['pdf'],
            mimeTypes: ['application/pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ];
        final other = await openFile(acceptedTypeGroups: types);
        final source = _sourcePath;
        if (other == null || source == null) return;
        final destination = await _chooseOutputPath('lexpdf_combinado.pdf');
        if (destination == null) return;
        await _largeService.mergeToFile(
          [source, other.path],
          outputPath: destination,
        );
        await _showSaved('PDF combinado salvo', destination);
      });

  Future<void> _imagesToPdf() => _run(() async {
        const types = <XTypeGroup>[
          XTypeGroup(
            label: 'Imagens',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
            uniformTypeIdentifiers: [
              'public.jpeg',
              'public.png',
              'org.webmproject.webp',
            ],
          ),
        ];
        final files = await openFiles(acceptedTypeGroups: types);
        if (files.isEmpty) return;
        final destination = await _chooseOutputPath('lexpdf_imagens.pdf');
        if (destination == null) return;
        await _largeService.imagesToPdfToFile(
          files.map((file) => file.path).toList(growable: false),
          outputPath: destination,
        );
        await _showSaved('PDF de imagens salvo', destination);
      });

  Future<void> _insertBlankPage() => _run(() async {
        final selectedIndexes = <int>[
          for (var i = 0; i < _pages.length; i++)
            if (_pages[i].selected) i,
        ];
        if (selectedIndexes.length > 1) {
          throw StateError(
            'Para inserir uma página em branco, selecione no máximo uma página.',
          );
        }
        final after = selectedIndexes.isEmpty
            ? _pages.length
            : selectedIndexes.single + 1;
        final destination =
            await _chooseOutputPath('lexpdf_com_pagina_em_branco.pdf');
        if (destination == null) return;
        await _withCurrentPlanPath(
          (path) => _largeService.addBlankPageToFile(
            sourcePath: path,
            outputPath: destination,
            afterPageNumber: after,
          ),
        );
        await _showSaved('PDF com página em branco salvo', destination);
      });

  Future<void> _insertImageOnSelectedPage() => _run(() async {
        final selectedIndexes = <int>[
          for (var i = 0; i < _pages.length; i++)
            if (_pages[i].selected) i,
        ];
        if (selectedIndexes.length != 1) {
          throw StateError(
            'Selecione exatamente uma página para inserir a imagem.',
          );
        }
        const types = <XTypeGroup>[
          XTypeGroup(
            label: 'Imagem',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
            uniformTypeIdentifiers: [
              'public.jpeg',
              'public.png',
              'org.webmproject.webp',
            ],
          ),
        ];
        final image = await openFile(acceptedTypeGroups: types);
        if (image == null) return;
        final destination = await _chooseOutputPath('lexpdf_com_imagem.pdf');
        if (destination == null) return;
        await _withCurrentPlanPath(
          (path) => _largeService.insertImageOnPageToFile(
            sourcePath: path,
            imagePath: image.path,
            pageNumber: selectedIndexes.single + 1,
            outputPath: destination,
          ),
        );
        await _showSaved('PDF com imagem inserida salvo', destination);
      });

  Future<void> _splitEveryPage() => _run(() async {
        final source = _sourcePath;
        if (source == null) return;
        String? directory;
        if (Platform.isWindows ||
            Platform.isLinux ||
            Platform.isMacOS ||
            Platform.isAndroid) {
          directory = await getDirectoryPath(canCreateDirectories: true);
        }
        if (directory == null) {
          final app = await getApplicationDocumentsDirectory();
          directory =
              '${app.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}split';
        }
        final count = await _service.splitEveryPageToDirectory(
          source,
          outputDirectory: Directory(directory),
        );
        await _showSaved('$count PDFs salvos em', directory);
      });

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _pages.length) return;
    setState(() {
      final page = _pages.removeAt(index);
      _pages.insert(target, page);
    });
  }

  void _duplicate(int index) {
    final source = _pages[index];
    setState(() {
      _pages.insert(
        index + 1,
        _PlannedPage(
          id: '${source.id}-copy-${DateTime.now().microsecondsSinceEpoch}',
          sourcePageNumber: source.sourcePageNumber,
          clockwiseQuarterTurns: source.clockwiseQuarterTurns,
        ),
      );
    });
  }

  void _delete(int index) {
    if (_pages.length <= 1) return;
    setState(() => _pages.removeAt(index));
  }

  void _selectAll(bool selected) {
    setState(() {
      for (final page in _pages) {
        page.selected = selected;
      }
    });
  }

  void _rotate(int index) {
    setState(() => _pages[index].clockwiseQuarterTurns++);
  }

  @override
  Widget build(BuildContext context) {
    final path = _sourcePath;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar páginas PDF'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy && !_loading,
            onSelected: (value) {
              if (value == 'blank') _insertBlankPage();
              if (value == 'insert_image') _insertImageOnSelectedPage();
              if (value == 'merge') _mergePdf();
              if (value == 'images') _imagesToPdf();
              if (value == 'split') _splitEveryPage();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'blank',
                child: Text('Inserir página em branco'),
              ),
              PopupMenuItem(
                value: 'insert_image',
                child: Text('Inserir imagem na página selecionada'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'merge',
                child: Text('Combinar com outro PDF'),
              ),
              PopupMenuItem(
                value: 'images',
                child: Text('Criar PDF de imagens'),
              ),
              PopupMenuItem(
                value: 'split',
                child: Text('Dividir em PDFs individuais'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Não foi possível abrir o PDF: $_error'))
              : path == null || path.isEmpty
                  ? const Center(child: Text('PDF indisponível offline.'))
                  : Column(
                      children: [
                        _buildTopBar(),
                        if (_busy) const LinearProgressIndicator(),
                        Expanded(child: _buildThumbnailGrid(path)),
                      ],
                    ),
    );
  }

  Widget _buildTopBar() {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final status = _selectedCount == 0
        ? '${_pages.length} páginas'
        : '$_selectedCount de ${_pages.length} selecionadas';

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: compact ? 220 : 300,
              child: Text(
                '$status • miniaturas renderizadas sob demanda',
                maxLines: 2,
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _selectAll(true),
              icon: const Icon(Icons.select_all_outlined),
              label: const Text('Selecionar todas'),
            ),
            if (_selectedCount > 0)
              TextButton.icon(
                onPressed: _busy ? null : () => _selectAll(false),
                icon: const Icon(Icons.deselect_outlined),
                label: const Text('Limpar seleção'),
              ),
            OutlinedButton.icon(
              onPressed: _busy || _selectedCount == 0 ? null : _extractSelected,
              icon: const Icon(Icons.content_cut),
              label: const Text('Extrair'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _savePlan,
              icon: const Icon(Icons.save_as_outlined),
              label: const Text('Salvar como'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailGrid(String path) {
    return PdfDocumentViewBuilder.file(
      path,
      builder: (context, document) {
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 315,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: _pages.length,
          itemBuilder: (context, index) {
            final page = _pages[index];
            return _buildPageCard(document, page, index);
          },
        );
      },
    );
  }

  Widget _buildPageCard(PdfDocument document, _PlannedPage page, int index) {
    final degrees = (page.clockwiseQuarterTurns % 4) * 90;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey(page.id),
      clipBehavior: Clip.antiAlias,
      color: page.selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: _busy
            ? null
            : () => setState(() => page.selected = !page.selected),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: RotatedBox(
                        quarterTurns: page.clockwiseQuarterTurns % 4,
                        child: PdfPageView(
                          document: document,
                          pageNumber: page.sourcePageNumber,
                          maximumDpi: 110,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Checkbox(
                      value: page.selected,
                      onChanged: _busy
                          ? null
                          : (value) => setState(
                                () => page.selected = value ?? false,
                              ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: PopupMenuButton<String>(
                      enabled: !_busy,
                      tooltip: 'Ações da página',
                      onSelected: (value) {
                        if (value == 'rotate') _rotate(index);
                        if (value == 'duplicate') _duplicate(index);
                        if (value == 'delete') _delete(index);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rotate',
                          child: Text('Girar 90°'),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicar'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled: _pages.length > 1,
                          child: const Text('Excluir'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                children: [
                  Text(
                    'Página ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    degrees == 0
                        ? 'Original ${page.sourcePageNumber}'
                        : 'Original ${page.sourcePageNumber} • $degrees°',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Mover uma posição para trás',
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy || index == 0
                            ? null
                            : () => _move(index, -1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Girar 90°',
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : () => _rotate(index),
                        icon: const Icon(Icons.rotate_right),
                      ),
                      IconButton(
                        tooltip: 'Mover uma posição para frente',
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy || index == _pages.length - 1
                            ? null
                            : () => _move(index, 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
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
