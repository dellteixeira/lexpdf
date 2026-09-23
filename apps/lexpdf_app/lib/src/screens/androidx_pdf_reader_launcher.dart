import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/documents/document_provider.dart';

/// Launches the native Google AndroidX PDF/Ink Activity.
///
/// The actual PDF is rendered outside Flutter in a dedicated Android process.
/// This keeps Android free of the legacy pdfrx/PDFium reader and avoids any
/// commercial SDK evaluation watermark.
class AndroidxPdfReaderLauncher extends StatefulWidget {
  const AndroidxPdfReaderLauncher({
    required this.document,
    required this.initialPage,
    required this.fullScreen,
    required this.onToggleFullScreen,
    super.key,
  });

  final DocumentRef document;
  final int initialPage;
  final bool fullScreen;
  final VoidCallback onToggleFullScreen;

  @override
  State<AndroidxPdfReaderLauncher> createState() =>
      _AndroidxPdfReaderLauncherState();
}

class _AndroidxPdfReaderLauncherState extends State<AndroidxPdfReaderLauncher> {
  static const MethodChannel _channel = MethodChannel('lexpdf/androidx_pdf');

  bool _opening = false;
  bool _openedOnce = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_opening) return;

    final path = widget.document.localPath;
    if (path == null || path.trim().isEmpty) {
      setState(() {
        _error = StateError('O PDF precisa estar disponível offline.');
      });
      return;
    }

    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      await _channel.invokeMethod<bool>('openDocument', <String, Object>{
        'path': path,
        'initialPage': widget.initialPage < 1 ? 1 : widget.initialPage,
      });
      if (!mounted) return;
      setState(() => _openedOnce = true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 64,
                  color: scheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Leitor AndroidX PDF + Ink',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.document.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _error != null
                      ? 'O leitor AndroidX não pôde ser iniciado.'
                      : _openedOnce
                          ? 'O documento foi aberto no leitor nativo do Google. '
                              'Toque abaixo para abri-lo novamente.'
                          : 'Abrindo o PDF em um processo Android dedicado, '
                              'sem SDK comercial e sem watermark de avaliação…',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    '$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _opening ? null : _open,
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(_opening ? 'Abrindo…' : 'Abrir no AndroidX PDF'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Em dispositivos com SDK Extension S ≥ 18, o viewer usa '
                  'EditablePdfViewerFragment + AndroidX Ink (caneta, marcador, '
                  'borracha e undo/redo). Em Extension 13–17, a leitura nativa '
                  'continua disponível, mas a edição Ink integrada fica '
                  'desativada.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                if (!widget.fullScreen) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: widget.onToggleFullScreen,
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('Tela cheia do workspace'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
