import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/documents/document_provider.dart';

/// Thin Flutter launcher for the native Apryse/Xodo-family Android viewer.
///
/// The actual PDF renderer lives entirely in Apryse DocumentActivity, which is
/// declared in AndroidManifest.xml with android:process=":apryse". Flutter does
/// not render pages, parse the PDF, OCR it, or hold native page caches on this
/// path.
class AndroidAprysePdfReaderScreen extends StatefulWidget {
  const AndroidAprysePdfReaderScreen({
    required this.document,
    required this.fullScreen,
    required this.onToggleFullScreen,
    super.key,
  });

  final DocumentRef document;
  final bool fullScreen;
  final VoidCallback onToggleFullScreen;

  @override
  State<AndroidAprysePdfReaderScreen> createState() =>
      _AndroidAprysePdfReaderScreenState();
}

class _AndroidAprysePdfReaderScreenState
    extends State<AndroidAprysePdfReaderScreen> {
  static const MethodChannel _channel = MethodChannel('lexpdf/apryse_viewer');

  bool _launching = false;
  bool _launchedOnce = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openNativeViewer();
    });
  }

  Future<void> _openNativeViewer() async {
    if (_launching) return;
    final path = widget.document.localPath;
    if (path == null || path.trim().isEmpty) {
      setState(() {
        _error = StateError('O PDF precisa estar disponível offline.');
      });
      return;
    }

    setState(() {
      _launching = true;
      _error = null;
    });

    try {
      await _channel.invokeMethod<bool>('openDocument', <String, Object>{
        'path': path,
      });
      if (!mounted) return;
      setState(() => _launchedOnce = true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 60,
                  color: scheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Leitor Apryse Android',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.document.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Text(
                  _error != null
                      ? 'O leitor nativo não pôde ser iniciado.'
                      : _launchedOnce
                          ? 'O documento foi aberto no motor Apryse. '
                              'Toque abaixo para abri-lo novamente.'
                          : 'Abrindo o PDF em um processo Android dedicado, '
                              'separado do Flutter e do PDFium…',
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
                  onPressed: _launching ? null : _openNativeViewer,
                  icon: _launching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(
                    _launching ? 'Abrindo…' : 'Abrir no leitor Apryse',
                  ),
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
