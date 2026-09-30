import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/documents/document_provider.dart';

class NativePdfReaderLauncher extends StatefulWidget {
  const NativePdfReaderLauncher({
    required this.document,
    required this.initialPage,
    required this.fullScreen,
    required this.onToggleFullScreen,
    required this.onPageChanged,
    super.key,
  });

  final DocumentRef document;
  final int initialPage;
  final bool fullScreen;
  final VoidCallback onToggleFullScreen;
  final ValueChanged<int> onPageChanged;

  @override
  State<NativePdfReaderLauncher> createState() => _NativePdfReaderLauncherState();
}

class _NativePdfReaderLauncherState extends State<NativePdfReaderLauncher> {
  static const _channel = MethodChannel('lexpdf/native_pdf_reader');

  bool _opening = false;
  bool _openedOnce = false;
  Object? _error;
  late int _resumePage;

  @override
  void initState() {
    super.initState();
    _resumePage = widget.initialPage < 1 ? 1 : widget.initialPage;
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
      final result =
          await _channel.invokeMapMethod<dynamic, dynamic>(
        'openDocument',
        <String, Object>{
          'path': path,
          'initialPage': _resumePage,
        },
      );
      final lastPage = result?['lastPage'];
      if (lastPage is int && lastPage >= 1) {
        _resumePage = lastPage;
        widget.onPageChanged(lastPage);
      }
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
          constraints: const BoxConstraints(maxWidth: 620),
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
                  'Leitor nativo Android',
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
                      ? 'O leitor nativo não pôde ser iniciado.'
                      : _openedOnce
                          ? 'O documento foi aberto pelo Mozilla PDF.js no WebView. '
                              'Toque abaixo para abri-lo novamente.'
                          : 'Abrindo em um processo Android separado com '
                              'PDF.js + streaming por faixa + AndroidX Ink, sem SDK comercial…',
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
                  label: Text(
                    _opening ? 'Abrindo…' : 'Abrir no leitor nativo',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'S Pen: escreve/desenha. Dedo: navega e faz zoom. '
                  'As anotações ficam em sidecar LexPDF por página, sem alterar '
                  'o PDF original durante a leitura.',
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
