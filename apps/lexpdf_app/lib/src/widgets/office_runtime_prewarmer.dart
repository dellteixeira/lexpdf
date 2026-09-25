import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Pré-aquece o processo WebView/Chromium e o runtime Office do LexPDF.
///
/// O widget é propositalmente invisível, não recebe interação e sai da árvore
/// após a inicialização. Assim, o primeiro acesso a Documentos Office evita
/// pagar todo o custo de cold start do WebView.
class OfficeRuntimePrewarmer extends StatefulWidget {
  const OfficeRuntimePrewarmer({super.key});

  @override
  State<OfficeRuntimePrewarmer> createState() => _OfficeRuntimePrewarmerState();
}

class _OfficeRuntimePrewarmerState extends State<OfficeRuntimePrewarmer> {
  bool _finished = false;
  bool _scheduledFinish = false;

  bool get _supported => Platform.isAndroid || Platform.isWindows;

  Future<void> _finishLater() async {
    if (_scheduledFinish) return;
    _scheduledFinish = true;
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _finished) return const SizedBox.shrink();

    return IgnorePointer(
      child: Opacity(
        opacity: 0.001,
        child: SizedBox.square(
          dimension: 1,
          child: InAppWebView(
            initialFile: 'assets/office_runtime/index.html',
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              supportZoom: false,
            ),
            onLoadStop: (controller, url) async {
              // O próprio runtime agenda o carregamento ocioso do docx-engine.
              // Esta chamada antecipa o warmup quando o bridge já estiver pronto.
              try {
                await controller.evaluateJavascript(
                  source:
                      'window.LexPdfOffice?.warmEngine?.().catch?.(() => {})',
                );
              } catch (_) {
                // Prewarm é oportunista: nunca deve afetar a inicialização do app.
              }
              unawaited(_finishLater());
            },
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame == true) {
                unawaited(_finishLater());
              }
            },
          ),
        ),
      ),
    );
  }
}
