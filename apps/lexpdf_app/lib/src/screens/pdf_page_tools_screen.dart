import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
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
  static const _writer = SafePdfWriter();
  final List<_PlannedPage> _pages = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  String? get _sourcePath => widget.document.localPath;

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
              id: 'page-${index + 1}-${DateTime.now().microsecondsSinceEpoch}-$index',
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

  Future<void> _saveBytes(
    Uint8List bytes,
    String suggestedName, {
    String successLabel = 'PDF salvo',
  }) async {
    final path = await _chooseOutputPath(suggestedName);
    if (path == null) return;
    await _writer.saveAs(
      bytes: bytes,
      destinationPath: path,
      replaceExisting: Platform.isAndroid || Platform.isIOS,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$successLabel: $path')),
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

  Future<T> _withComposedTemp<T>(Future<T> Function(String path) action) async {
    if (_pages.isEmpty) throw StateError('O documento não pode ficar sem páginas.');
    final bytes = await _service.compose(_specs(_pages));
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lexpdf-plan-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await action(file.path);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _savePlan() => _run(() async {
        if (_pages.isEmpty) throw StateError('O documento não pode ficar sem páginas.');
        final bytes = await _service.compose(_specs(_pages));
        await _saveBytes(bytes, 'lexpdf_editado.pdf');
      });

  Future<void> _extractSelected() => _run(() async {
        final selected = _pages.where((page) => page.selected).toList();
        if (selected.isEmpty) throw StateError('Selecione pelo menos uma página.');
        final bytes = await _service.compose(
          _specs(selected),
          sourceName: 'extracao.pdf',
        );
        await _saveBytes(bytes, 'lexpdf_paginas_extraidas.pdf');
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
        final bytes = await _service.merge([source, other.path]);
        await _saveBytes(bytes, 'lexpdf_combinado.pdf');
      });

  Future<void> _imagesToPdf() => _run(() async {
        const types = <XTypeGroup>[
          XTypeGroup(
            label: 'Imagens',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png', 'org.webmproject.webp'],
          ),
        ];
        final files = await openFiles(acceptedTypeGroups: types);
        if (files.isEmpty) return;
        final bytes = await _service.imagesToPdf(files.map((file) => file.path).toList());
        await _saveBytes(bytes, 'lexpdf_imagens.pdf');
      });

  Future<void> _insertBlankPage() => _run(() async {
        final selectedIndexes = <int>[
          for (var i = 0; i < _pages.length; i++)
            if (_pages[i].selected) i,
        ];
        if (selectedIndexes.length > 1) {
          throw StateError('Para inserir uma página em branco, selecione no máximo uma página.');
        }
        final after = selectedIndexes.isEmpty ? _pages.length : selectedIndexes.single + 1;
        final bytes = await _withComposedTemp(
          (path) => _service.addBlankPage(path, afterPageNumber: after),
        );
        await _saveBytes(bytes, 'lexpdf_com_pagina_em_branco.pdf');
      });

  Future<void> _insertImageOnSelectedPage() => _run(() async {
        final selectedIndexes = <int>[
          for (var i = 0; i < _pages.length; i++)
            if (_pages[i].selected) i,
        ];
        if (selectedIndexes.length != 1) {
          throw StateError('Selecione exatamente uma página para inserir a imagem.');
        }
        const types = <XTypeGroup>[
          XTypeGroup(
            label: 'Imagem',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png', 'org.webmproject.webp'],
          ),
        ];
        final image = await openFile(acceptedTypeGroups: types);
        if (image == null) return;
        final bytes = await _withComposedTemp(
          (path) => _service.insertImageOnPage(
            sourcePath: path,
            imagePath: image.path,
            pageNumber: selectedIndexes.single + 1,
          ),
        );
        await _saveBytes(
          bytes,
          'lexpdf_com_imagem.pdf',
          successLabel: 'PDF com imagem inserida salvo',
        );
      });

  Future<void> _splitEveryPage() => _run(() async {
        final source = _sourcePath;
        if (source == null) return;
        final outputs = await _service.splitEveryPage(source);
        if (outputs.isEmpty) return;
        String? directory;
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
          directory = await getDirectoryPath(canCreateDirectories: true);
        }
        if (directory == null) {
          final app = await getApplicationDocumentsDirectory();
          directory = '${app.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}split';
        }
        await Directory(directory).create(recursive: true);
        for (var index = 0; index < outputs.length; index++) {
          await _writer.saveAs(
            bytes: outputs[index],
            destinationPath: '$directory${Platform.pathSeparator}pagina_${index + 1}.pdf',
            replaceExisting: true,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${outputs.length} PDFs salvos em: $directory')),
          );
        }
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

  @override
  Widget build(BuildContext context) {
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
              PopupMenuItem(value: 'blank', child: Text('Inserir página em branco')),
              PopupMenuItem(value: 'insert_image', child: Text('Inserir imagem na página selecionada')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'merge', child: Text('Combinar com outro PDF')),
              PopupMenuItem(value: 'images', child: Text('Criar PDF de imagens')),
              PopupMenuItem(value: 'split', child: Text('Dividir em PDFs individuais')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Não foi possível abrir o PDF: $_error'))
              : Column(
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_pages.length} páginas • o original não é sobrescrito por padrão',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _extractSelected,
                              icon: const Icon(Icons.content_cut),
                              label: const Text('Extrair selecionadas'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _busy ? null : _savePlan,
                              icon: const Icon(Icons.save_as_outlined),
                              label: const Text('Salvar como'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _pages.length,
                        onReorderItem: _busy
                            ? (_, __) {}
                            : (oldIndex, newIndex) {
                                setState(() {
                                  final item = _pages.removeAt(oldIndex);
                                  _pages.insert(newIndex, item);
                                });
                              },
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          final degrees = (page.clockwiseQuarterTurns % 4) * 90;
                          return Card(
                            key: ValueKey(page.id),
                            child: ListTile(
                              leading: Checkbox(
                                value: page.selected,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() => page.selected = value ?? false),
                              ),
                              title: Text('Página original ${page.sourcePageNumber}'),
                              subtitle: Text('Rotação aplicada: $degrees°'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Mover para cima',
                                    onPressed: _busy || index == 0 ? null : () => _move(index, -1),
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: 'Mover para baixo',
                                    onPressed: _busy || index == _pages.length - 1
                                        ? null
                                        : () => _move(index, 1),
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                  IconButton(
                                    tooltip: 'Girar 90°',
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() => page.clockwiseQuarterTurns++),
                                    icon: const Icon(Icons.rotate_right),
                                  ),
                                  IconButton(
                                    tooltip: 'Duplicar',
                                    onPressed: _busy ? null : () => _duplicate(index),
                                    icon: const Icon(Icons.copy_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir',
                                    onPressed: _busy || _pages.length <= 1 ? null : () => _delete(index),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                  const Icon(Icons.drag_handle),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
