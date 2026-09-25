import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

class OfficeDocumentScreen extends StatefulWidget {
  const OfficeDocumentScreen({super.key});

  @override
  State<OfficeDocumentScreen> createState() => _OfficeDocumentScreenState();
}

class _OfficeDocumentScreenState extends State<OfficeDocumentScreen> {
  static const _mime =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  InAppWebViewController? _controller;
  bool _runtimeLoaded = false;
  bool _busy = false;
  bool _dirty = false;
  String? _documentName;

  XTypeGroup get _docxType => Platform.isAndroid
      ? const XTypeGroup(
          label: 'Documento Word',
          extensions: <String>['docx'],
          mimeTypes: <String>[_mime],
        )
      : const XTypeGroup(
          label: 'Documento Word',
          extensions: <String>['docx'],
        );

  Future<void> _pickAndOpen() async {
    if (_busy || !_runtimeLoaded) return;
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[_docxType],
      confirmButtonText: 'Abrir',
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final base64 = base64Encode(await file.readAsBytes());
      final name = file.name.isEmpty ? 'documento.docx' : file.name;
      await _controller!.evaluateJavascript(
        source:
            'window.LexPdfOffice.openBase64(' +
            jsonEncode(base64) +
            ', ' +
            jsonEncode(name) +
            ')',
      );
      if (!mounted) return;
      setState(() {
        _documentName = name;
        _dirty = false;
      });
    } catch (error) {
      _show('Não foi possível abrir o DOCX: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _savedBytes() async {
    final result = await _controller!.evaluateJavascript(
      source: 'JSON.stringify(await window.LexPdfOffice.saveBase64())',
    );
    if (result == null) throw StateError('O editor não retornou o DOCX.');
    final decoded = jsonDecode(result is String ? result : result.toString());
    if (decoded is! Map || decoded['base64'] is! String) {
      throw StateError('Resposta inválida do editor DOCX.');
    }
    return base64Decode(decoded['base64'] as String);
  }

  Future<void> _save() async {
    if (_busy || _documentName == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _savedBytes();
      if (Platform.isWindows) {
        final target = await getSaveLocation(
          acceptedTypeGroups: <XTypeGroup>[_docxType],
          suggestedName: _outputName,
          confirmButtonText: 'Salvar',
        );
        if (target == null) return;
        await XFile.fromData(bytes, mimeType: _mime, name: _outputName)
            .saveTo(target.path);
        _show('DOCX salvo com sucesso.');
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final target = File(
          directory.path + Platform.pathSeparator + _outputName,
        );
        await target.writeAsBytes(bytes, flush: true);
        _show('Cópia salva em: ' + target.path);
      }
      if (mounted) setState(() => _dirty = false);
    } catch (error) {
      _show('Não foi possível salvar o DOCX: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    final name = _documentName ?? 'documento.docx';
    final base = name.toLowerCase().endsWith('.docx')
        ? name.substring(0, name.length - 5)
        : name;
    return base + '-lexpdf.docx';
  }

  Future<void> _command(String command) async {
    if (!_runtimeLoaded || _controller == null) return;
    await _controller!.evaluateJavascript(
      source: 'window.LexPdfOffice.' + command + '()',
    );
  }

  void _runtimeEvent(List<dynamic> args) {
    if (args.isEmpty) return;
    dynamic event = args.first;
    if (event is String) {
      try {
        event = jsonDecode(event);
      } catch (_) {
        return;
      }
    }
    if (event is! Map) return;
    final type = event['type'];
    if (!mounted) return;
    if (type == 'ready') setState(() => _runtimeLoaded = true);
    if (type == 'documentChanged') setState(() => _dirty = true);
    if (type == 'documentOpened' || type == 'documentSaved') {
      setState(() => _dirty = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmClose() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Descartar alterações?'),
            content: const Text(
              'Este DOCX possui alterações que ainda não foram salvas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Continuar editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmClose,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_documentName ?? 'Documentos Office'),
          actions: [
            IconButton(
              tooltip: 'Abrir DOCX',
              onPressed: _busy || !_runtimeLoaded ? null : _pickAndOpen,
              icon: const Icon(Icons.file_open_outlined),
            ),
            IconButton(
              tooltip: 'Desfazer',
              onPressed: _runtimeLoaded ? () => _command('undo') : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Refazer',
              onPressed: _runtimeLoaded ? () => _command('redo') : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: 'Salvar DOCX',
              onPressed: _busy || _documentName == null ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/office_runtime/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'LexPdfOfficeEvent',
                  callback: (args) {
                    _runtimeEvent(args);
                    return <String, Object?>{'ok': true};
                  },
                );
              },
              onLoadStop: (controller, url) {
                if (mounted) setState(() => _runtimeLoaded = true);
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame == true) {
                  _show('Falha ao carregar o editor Office.');
                }
              },
            ),
            if (_busy || !_runtimeLoaded)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.72),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_runtimeLoaded && _documentName == null && !_busy)
              Positioned.fill(
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.description_outlined, size: 48),
                            const SizedBox(height: 14),
                            Text(
                              'Editor DOCX profissional',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Abra um arquivo .docx para editar localmente com o motor GenOffice.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _pickAndOpen,
                              icon: const Icon(Icons.file_open_outlined),
                              label: const Text('Abrir DOCX'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
