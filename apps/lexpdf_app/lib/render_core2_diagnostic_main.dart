import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/core/pdf/lexpdf_render_surface.dart';
import 'src/core/pdf/render_core2_backend.dart';
import 'src/core/pdf/render_core2_windows_pdfium_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RenderCore2DiagnosticApp());
}

class RenderCore2DiagnosticApp extends StatelessWidget {
  const RenderCore2DiagnosticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LexPDF Render Core 2 Diagnostic',
      theme: ThemeData(useMaterial3: true),
      home: const RenderCore2DiagnosticScreen(),
    );
  }
}

class RenderCore2DiagnosticScreen extends StatefulWidget {
  const RenderCore2DiagnosticScreen({super.key});

  @override
  State<RenderCore2DiagnosticScreen> createState() =>
      _RenderCore2DiagnosticScreenState();
}

class _RenderCore2DiagnosticScreenState
    extends State<RenderCore2DiagnosticScreen> {
  static const _zoomPresets = <int>[75, 100, 125, 200, 300, 400];
  static const _pdfGroup = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
  );

  final RenderCore2WindowsPdfiumBackend _backend =
      RenderCore2WindowsPdfiumBackend();

  String? _documentPath;
  RenderCore2PdfPageInfo? _pageInfo;
  ui.Image? _image;
  String? _error;
  int _pageNumber = 1;
  int _zoomPercent = 100;
  int _generation = 0;
  int? _requestedWidth;
  int? _requestedHeight;
  int? _returnedWidth;
  int? _returnedHeight;
  int? _rowBytes;
  double? _lastDpr;
  bool _busy = false;

  bool get _featureEnabled =>
      RenderCore2BackendPolicy.isNativePrototypeEnabled();

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    unawaited(_backend.close());
    super.dispose();
  }

  Future<void> _selectPdf() async {
    if (!_featureEnabled) return;
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[_pdfGroup]);
    if (file == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _backend.close();
      await _backend.open(file.path);
      final info = await _backend.getPageInfo(1);
      if (!mounted) return;
      setState(() {
        _documentPath = file.path;
        _pageNumber = 1;
        _pageInfo = info;
      });
      await _renderCurrentPage();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePage(int delta) async {
    final info = _pageInfo;
    if (_documentPath == null || info == null || _busy) return;
    final target = (_pageNumber + delta).clamp(1, info.pageCount);
    if (target == _pageNumber) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await _backend.getPageInfo(target);
      if (!mounted) return;
      setState(() {
        _pageNumber = target;
        _pageInfo = next;
      });
      await _renderCurrentPage();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeZoom(int zoomPercent) async {
    if (_documentPath == null || _pageInfo == null || _busy) return;
    if (_zoomPercent == zoomPercent) return;
    setState(() {
      _zoomPercent = zoomPercent;
      _busy = true;
      _error = null;
    });
    try {
      await _renderCurrentPage();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renderCurrentPage() async {
    final path = _documentPath;
    final info = _pageInfo;
    if (path == null || info == null || !mounted) return;

    final dpr = View.of(context).devicePixelRatio;
    final viewerZoom = _zoomPercent / 100.0;
    final logicalWidth = info.widthPoints * viewerZoom;
    final logicalHeight = info.heightPoints * viewerZoom;
    final pixelWidth = (logicalWidth * dpr).ceil();
    final pixelHeight = (logicalHeight * dpr).ceil();
    if (pixelWidth <= 0 || pixelHeight <= 0 ||
        pixelWidth > 32768 || pixelHeight > 32768) {
      throw StateError(
        'Requested physical raster is outside the diagnostic safety limit: '
        '${pixelWidth}x$pixelHeight.',
      );
    }

    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _requestedWidth = pixelWidth;
        _requestedHeight = pixelHeight;
        _lastDpr = dpr;
      });
    }

    final frame = await _backend.renderPage(
      LexPdfRenderRequest(
        documentPath: path,
        pageNumber: _pageNumber,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        devicePixelRatio: dpr,
        viewerZoom: viewerZoom,
        generation: generation,
      ),
    );
    if (!mounted || generation != _generation || frame.generation != generation) {
      return;
    }

    final image = await _decode(frame);
    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }

    final previous = _image;
    setState(() {
      _image = image;
      _returnedWidth = frame.width;
      _returnedHeight = frame.height;
      _rowBytes = frame.rowBytes;
      _error = null;
    });
    previous?.dispose();
  }

  Future<ui.Image> _decode(LexPdfRenderFrame frame) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.bgra8888,
      frame.width,
      frame.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
      rowBytes: frame.rowBytes,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return const Scaffold(
        body: Center(
          child: Text('Render Core 2 diagnostic is Windows-only.'),
        ),
      );
    }

    if (!_featureEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Render Core 2 Diagnostic')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SelectableText(
              'Native prototype is disabled. Start this target with:\n\n'
              'flutter run -d windows -t lib/render_core2_diagnostic_main.dart '
              '--dart-define=LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE=true',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final info = _pageInfo;
    final zoom = _zoomPercent / 100.0;
    final logicalWidth = info == null ? null : info.widthPoints * zoom;
    final logicalHeight = info == null ? null : info.heightPoints * zoom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Render Core 2 — PDFium Diagnostic'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _selectPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Abrir PDF'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Material(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Página anterior',
                    onPressed: info != null && _pageNumber > 1 && !_busy
                        ? () => _changePage(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    info == null
                        ? 'Sem documento'
                        : 'Página $_pageNumber/${info.pageCount}',
                  ),
                  IconButton(
                    tooltip: 'Próxima página',
                    onPressed: info != null &&
                            _pageNumber < info.pageCount &&
                            !_busy
                        ? () => _changePage(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 8),
                  for (final preset in _zoomPresets)
                    ChoiceChip(
                      label: Text('$preset%'),
                      selected: preset == _zoomPercent,
                      onSelected: _busy ? null : (_) => _changeZoom(preset),
                    ),
                  if (_busy)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          if (_error != null)
            MaterialBanner(
              content: SelectableText(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          Expanded(
            child: _image == null || logicalWidth == null || logicalHeight == null
                ? const Center(
                    child: Text('Abra um PDF para iniciar o teste físico.'),
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: RawImage(
                              image: _image,
                              width: logicalWidth,
                              height: logicalHeight,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (info != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              color: Theme.of(context).colorScheme.surface,
              child: SelectableText(
                'backend=${_backend.backendName}  '
                'PDF=${info.widthPoints.toStringAsFixed(2)}x${info.heightPoints.toStringAsFixed(2)} pt  '
                'zoom=$_zoomPercent%  DPR=${_lastDpr?.toStringAsFixed(3) ?? '-'}  '
                'requested=${_requestedWidth ?? '-'}x${_requestedHeight ?? '-'} px  '
                'returned=${_returnedWidth ?? '-'}x${_returnedHeight ?? '-'} px  '
                'rowBytes=${_rowBytes ?? '-'}',
              ),
            ),
        ],
      ),
    );
  }
}
