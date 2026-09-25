import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/office_runtime_prewarmer.dart';

class OfficeDocumentScreen extends StatefulWidget {
  const OfficeDocumentScreen({super.key});

  @override
  State<OfficeDocumentScreen> createState() => _OfficeDocumentScreenState();
}

class _OfficeDocumentScreenState extends State<OfficeDocumentScreen> {
  static const _mime =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  final OfficeWebViewRuntime _runtime = OfficeWebViewRuntime.instance;
  StreamSubscription<Map<String, dynamic>>? _runtimeSubscription;

  InAppWebViewController? _controller;
  bool _runtimeLoaded = false;
  bool _busy = false;
  bool _dirty = false;
  String _documentName = 'Sem título.docx';

  @override
  void initState() {
    super.initState();
    _controller = _runtime.controller;
    _runtimeLoaded = _runtime.ready;
    _dirty = _runtime.dirty;
    _documentName = _runtime.documentName;
    _runtimeSubscription = _runtime.events.listen(
      (event) => _runtimeEvent(<dynamic>[event]),
    );
  }

  @override
  void dispose() {
    _runtimeSubscription?.cancel();
    super.dispose();
  }

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

  Future<bool> _confirmReplaceIfNeeded() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Descartar alterações?'),
            content: const Text(
              'O documento atual possui alterações que ainda não foram salvas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
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

  Future<void> _newDocument() async {
    if (_busy || !_runtimeLoaded || _controller == null) return;
    if (!await _confirmReplaceIfNeeded()) return;

    setState(() => _busy = true);
    try {
      await _controller!.evaluateJavascript(
        source: 'window.LexPdfOffice.newDocument("Sem título.docx")',
      );
      if (!mounted) return;
      setState(() {
        _documentName = 'Sem título.docx';
        _dirty = false;
      });
    } catch (error) {
      _show('Não foi possível criar o documento: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndOpen() async {
    if (_busy || !_runtimeLoaded || _controller == null) return;
    if (!await _confirmReplaceIfNeeded()) return;

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
      _show('Não foi possível abrir o DOCX: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _savedBytes() async {
    final controller = _controller;
    if (controller == null || !_runtimeLoaded) {
      throw StateError('O editor Office ainda não está pronto.');
    }

    final result = await controller.evaluateJavascript(
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
    if (_busy || !_runtimeLoaded) return;
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
        _show('DOCX salvo com sucesso.');
      }

      if (mounted) setState(() => _dirty = false);
    } catch (error) {
      _show('Não foi possível salvar o DOCX: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    final base = _documentName.toLowerCase().endsWith('.docx')
        ? _documentName.substring(0, _documentName.length - 5)
        : _documentName;
    return base + '.docx';
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
    if (event is! Map || !mounted) return;

    final type = event['type'];
    final name = event['name'];

    if (type == 'ready') {
      setState(() {
        _runtimeLoaded = true;
        if (name is String && name.isNotEmpty) _documentName = name;
        _dirty = false;
      });
      return;
    }

    if (type == 'documentOpened') {
      setState(() {
        if (name is String && name.isNotEmpty) _documentName = name;
        _dirty = false;
      });
      return;
    }

    if (type == 'documentChanged') {
      setState(() => _dirty = true);
      return;
    }

    if (type == 'documentSaved') {
      setState(() => _dirty = false);
      return;
    }

    if (type == 'runtimeError') {
      _show(
        'Falha no editor Office: ' +
            (event['message']?.toString() ?? 'erro desconhecido'),
      );
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _formatButton({
    required String tooltip,
    required Widget child,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: _runtimeLoaded && !_busy ? onPressed : null,
      icon: child,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_dirty) return;
        final discard = await _confirmReplaceIfNeeded();
        if (!discard || !mounted) return;
        setState(() => _dirty = false);
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _documentName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('•'),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Novo documento',
              onPressed: _busy || !_runtimeLoaded ? null : _newDocument,
              icon: const Icon(Icons.note_add_outlined),
            ),
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
              onPressed: _busy || !_runtimeLoaded ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Material(
              elevation: 1,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    _formatButton(
                      tooltip: 'Negrito',
                      child: const Text(
                        'B',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _command('toggleBold'),
                    ),
                    _formatButton(
                      tooltip: 'Itálico',
                      child: const Text(
                        'I',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                      onPressed: () => _command('toggleItalic'),
                    ),
                    _formatButton(
                      tooltip: 'Sublinhado',
                      child: const Text(
                        'U',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      onPressed: () => _command('toggleUnderline'),
                    ),
                    _formatButton(
                      tooltip: 'Tachado',
                      child: const Text(
                        'S',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      onPressed: () => _command('toggleStrike'),
                    ),
                    const VerticalDivider(width: 24, indent: 9, endIndent: 9),
                    Text(
                      _runtimeLoaded ? 'DOCX' : 'Carregando editor…',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    keepAlive: _runtime.keepAlive,
                    initialFile: 'assets/office_runtime/index.html',
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      supportZoom: true,
                      transparentBackground: false,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      _runtime.registerController(controller);
                      if (mounted && _runtime.ready && !_runtimeLoaded) {
                        setState(() {
                          _runtimeLoaded = true;
                          _dirty = _runtime.dirty;
                          _documentName = _runtime.documentName;
                        });
                      }
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame == true) {
                        _show('Falha ao carregar o editor Office.');
                      }
                    },
                  ),
                  if (_busy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.72),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
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
