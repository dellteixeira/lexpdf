import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/documents/document_provider.dart';
import '../core/pdf/lexpdf_export_service.dart';
import '../core/pdf/safe_pdf_writer.dart';
import '../core/storage/local_database.dart';
import '../core/storage/local_pdf_annotation_object_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_text_annotation_store.dart';

class PdfExportScreen extends StatefulWidget {
  const PdfExportScreen({
    required this.document,
    required this.db,
    super.key,
  });

  final DocumentRef document;
  final LocalDatabase db;

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  late final LexPdfExportService _exporter;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _exporter = LexPdfExportService(
      textStore: LocalTextAnnotationStore(widget.db),
      inkStore: LocalPdfInkStore(widget.db),
      objectStore: LocalPdfAnnotationObjectStore(widget.db),
    );
  }

  Future<String?> _savePath(String name) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return (await getSaveLocation(suggestedName: name))?.path;
    }
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}exports',
    );
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$name';
  }

  Future<void> _execute(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exportação não concluída: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportEditable() => _execute(() async {
        final source = widget.document.localPath;
        if (source == null || source.isEmpty) {
          throw StateError('O PDF precisa estar disponível offline.');
        }
        final bytes = await _exporter.exportEditableBundle(
          documentId: widget.document.id,
          sourcePath: source,
        );
        final path = await _savePath('lexpdf_editavel.lexpdf');
        if (path == null) return;
        final temp = File('$path.tmp');
        try {
          await temp.writeAsBytes(bytes, flush: true);
          final target = File(path);
          if (await target.exists()) await target.delete();
          await temp.rename(path);
        } catch (_) {
          if (await temp.exists()) await temp.delete();
          rethrow;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Projeto LexPDF salvo: $path')),
          );
        }
      });

  Future<bool> _confirmFlattenedExport() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exportar PDF achatado?'),
            content: const Text(
              'Este formato prioriza fidelidade visual e rasteriza o conteúdo-base. '
              'Texto pesquisável/selecionável, acessibilidade e elementos vetoriais podem ser perdidos no arquivo exportado. '
              'O PDF original não será alterado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Exportar mesmo assim'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _exportFlattened() async {
    if (!await _confirmFlattenedExport()) return;
    await _execute(() async {
      final source = widget.document.localPath;
      if (source == null || source.isEmpty) {
        throw StateError('O PDF precisa estar disponível offline.');
      }
      final bytes = await _exporter.exportFlattenedPdf(
        documentId: widget.document.id,
        sourcePath: source,
      );
      final path = await _savePath('lexpdf_achatado.pdf');
      if (path == null) return;
      await const SafePdfWriter().saveAs(
        bytes: bytes,
        destinationPath: path,
        replaceExisting: Platform.isAndroid || Platform.isIOS,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF universal salvo: $path')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar PDF anotado')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'O arquivo original não é modificado. Escolha o formato conforme a necessidade de continuar editando ou compartilhar com outros leitores.',
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 28),
            _ExportCard(
              icon: Icons.layers_outlined,
              title: 'LexPDF editável',
              subtitle:
                  'Preserva o PDF original e as camadas de tinta, marcações, notas, formas, carimbos e assinaturas para reedição futura no LexPDF.',
              action: 'Exportar .lexpdf',
              onPressed: _busy ? null : _exportEditable,
            ),
            const SizedBox(height: 16),
            _ExportCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF universal achatado',
              subtitle:
                  'Gera um novo PDF visualmente consolidado por rasterização. Pode perder texto selecionável/pesquisável, acessibilidade e elementos vetoriais; o original permanece intacto.',
              action: 'Exportar PDF',
              onPressed: _busy ? null : _exportFlattened,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 42),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 18),
            FilledButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
