import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/pdf/pdf_document_tool_service.dart';

class PdfToolsScreen extends StatefulWidget {
  const PdfToolsScreen({super.key});

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  static const _pdfGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
  static const _imageGroup = XTypeGroup(
    label: 'Imagens',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
  );

  final PdfDocumentToolService _tools = const PdfDocumentToolService();
  XFile? _source;
  bool _busy = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final sourceName = _source?.name ?? 'Nenhum PDF selecionado';
    return Scaffold(
      appBar: AppBar(title: const Text('Ferramentas de PDF')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, size: 34),
                title: Text(sourceName),
                subtitle: const Text('O original não é sobrescrito por padrão.'),
                trailing: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickSource,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Selecionar'),
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: GridView.extent(
                maxCrossAxisExtent: 300,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _ToolCard(
                    icon: Icons.swap_vert,
                    title: 'Reordenar páginas',
                    subtitle: 'Ex.: 3,1,2,4-8',
                    enabled: _source != null && !_busy,
                    onTap: _reorder,
                  ),
                  _ToolCard(
                    icon: Icons.rotate_right,
                    title: 'Girar páginas',
                    subtitle: '90°, 180° ou 270°',
                    enabled: _source != null && !_busy,
                    onTap: _rotate,
                  ),
                  _ToolCard(
                    icon: Icons.delete_sweep_outlined,
                    title: 'Excluir páginas',
                    subtitle: 'Gera uma nova cópia segura',
                    enabled: _source != null && !_busy,
                    onTap: _deletePages,
                  ),
                  _ToolCard(
                    icon: Icons.copy_all_outlined,
                    title: 'Duplicar página',
                    subtitle: 'Insere a cópia após a original',
                    enabled: _source != null && !_busy,
                    onTap: _duplicate,
                  ),
                  _ToolCard(
                    icon: Icons.content_cut_outlined,
                    title: 'Extrair páginas',
                    subtitle: 'Cria um novo PDF com a seleção',
                    enabled: _source != null && !_busy,
                    onTap: _extract,
                  ),
                  _ToolCard(
                    icon: Icons.call_merge_outlined,
                    title: 'Combinar PDFs',
                    subtitle: 'Une vários PDFs na ordem escolhida',
                    enabled: !_busy,
                    onTap: _combine,
                  ),
                  _ToolCard(
                    icon: Icons.vertical_split_outlined,
                    title: 'Dividir PDF',
                    subtitle: 'Um PDF por página',
                    enabled: _source != null && !_busy,
                    onTap: _split,
                  ),
                  _ToolCard(
                    icon: Icons.photo_library_outlined,
                    title: 'Imagens para PDF',
                    subtitle: 'JPG, PNG ou WebP',
                    enabled: !_busy,
                    onTap: _imagesToPdf,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSource() async {
    final value = await openFile(acceptedTypeGroups: const [_pdfGroup]);
    if (value != null && mounted) {
      setState(() {
        _source = value;
        _status = '';
      });
    }
  }

  Future<void> _reorder() async {
    final pages = await _askPages('Nova ordem das páginas', 'Ex.: 3,1,2,4-8');
    if (pages == null) return;
    final output = await _chooseOutput('reordenado.pdf');
    if (output == null) return;
    await _run(() => _tools.reorder(
          sourcePath: _source!.path,
          pageOrder: pages,
          outputPath: output,
        ));
  }

  Future<void> _rotate() async {
    final pages = await _askPages('Páginas para girar', 'Ex.: 1,3-5');
    if (pages == null) return;
    if (!mounted) return;
    final rotation = await showDialog<PdfPageRotation>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Rotação'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, PdfPageRotation.clockwise90),
            child: const Text('90° horário'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, PdfPageRotation.clockwise180),
            child: const Text('180°'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, PdfPageRotation.clockwise270),
            child: const Text('270° horário'),
          ),
        ],
      ),
    );
    if (rotation == null) return;
    final output = await _chooseOutput('girado.pdf');
    if (output == null) return;
    await _run(() => _tools.rotate(
          sourcePath: _source!.path,
          pages: pages.toSet(),
          rotation: rotation,
          outputPath: output,
        ));
  }

  Future<void> _deletePages() async {
    final pages = await _askPages('Excluir páginas', 'Ex.: 2,4-6');
    if (pages == null) return;
    final output = await _chooseOutput('sem-paginas.pdf');
    if (output == null) return;
    await _run(() => _tools.deletePages(
          sourcePath: _source!.path,
          pages: pages.toSet(),
          outputPath: output,
        ));
  }

  Future<void> _duplicate() async {
    final pages = await _askPages('Página para duplicar', 'Ex.: 3');
    if (pages == null || pages.length != 1) return;
    final output = await _chooseOutput('duplicado.pdf');
    if (output == null) return;
    await _run(() => _tools.duplicatePage(
          sourcePath: _source!.path,
          pageNumber: pages.single,
          outputPath: output,
        ));
  }

  Future<void> _extract() async {
    final pages = await _askPages('Extrair páginas', 'Ex.: 1-3,7');
    if (pages == null) return;
    final output = await _chooseOutput('extraido.pdf');
    if (output == null) return;
    await _run(() => _tools.extractPages(
          sourcePath: _source!.path,
          pages: pages,
          outputPath: output,
        ));
  }

  Future<void> _combine() async {
    final values = await openFiles(acceptedTypeGroups: const [_pdfGroup]);
    if (values.length < 2) return;
    final output = await _chooseOutput('combinado.pdf');
    if (output == null) return;
    await _run(() => _tools.combine(
          sourcePaths: values.map((value) => value.path).toList(),
          outputPath: output,
        ));
  }

  Future<void> _split() async {
    final directory = await getDirectoryPath(confirmButtonText: 'Usar pasta');
    if (directory == null) return;
    await _run(() async {
      final values = await _tools.splitEachPage(
        sourcePath: _source!.path,
        outputDirectory: directory,
        baseName: _baseName(_source!.name),
      );
      return PdfSafeWriteResult(
        outputPath: directory,
        pageCount: values.length,
      );
    });
  }

  Future<void> _imagesToPdf() async {
    final values = await openFiles(acceptedTypeGroups: const [_imageGroup]);
    if (values.isEmpty) return;
    final output = await _chooseOutput('imagens.pdf');
    if (output == null) return;
    await _run(() => _tools.imagesToPdf(
          imagePaths: values.map((value) => value.path).toList(),
          outputPath: output,
        ));
  }

  Future<String?> _chooseOutput(String name) async {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [_pdfGroup],
    );
    return location?.path;
  }

  Future<List<int>?> _askPages(String title, String hint) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return null;
    try {
      return _parsePages(value);
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seleção de páginas inválida: $error')),
      );
      return null;
    }
  }

  List<int> _parsePages(String raw) {
    final result = <int>[];
    for (final part in raw.split(',')) {
      final value = part.trim();
      if (value.isEmpty) continue;
      if (!value.contains('-')) {
        final page = int.parse(value);
        if (page < 1) throw const FormatException('página deve ser >= 1');
        result.add(page);
        continue;
      }
      final bounds = value.split('-');
      if (bounds.length != 2) throw FormatException('intervalo inválido: $value');
      final start = int.parse(bounds[0].trim());
      final end = int.parse(bounds[1].trim());
      if (start < 1 || end < start) throw FormatException('intervalo inválido: $value');
      for (var page = start; page <= end; page++) result.add(page);
    }
    if (result.isEmpty) throw const FormatException('nenhuma página informada');
    return result;
  }

  Future<void> _run(Future<PdfSafeWriteResult> Function() task) async {
    setState(() {
      _busy = true;
      _status = 'Processando…';
    });
    try {
      final result = await task();
      if (!mounted) return;
      setState(() => _status = 'Concluído: ${result.outputPath} • ${result.pageCount} página(s)');
    } catch (error) {
      if (mounted) setState(() => _status = 'Falha: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(icon, size: 38),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
      ),
    );
  }
}
