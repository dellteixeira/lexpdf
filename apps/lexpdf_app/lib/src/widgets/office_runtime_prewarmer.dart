import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Runtime compartilhado do editor Office.
///
/// A mesma WebView nativa é usada no prewarm da home e na tela do editor.
/// Isso evita recriar Chromium/WebView, recarregar HTML/JS e remontar o Tiptap
/// a cada abertura de Documentos Office.
class OfficeWebViewRuntime {
  OfficeWebViewRuntime._();

  static final OfficeWebViewRuntime instance = OfficeWebViewRuntime._();

  final InAppWebViewKeepAlive keepAlive = InAppWebViewKeepAlive();
  final ValueNotifier<bool> backgroundAttached = ValueNotifier<bool>(true);

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  final Set<int> _registeredControllers = <int>{};

  InAppWebViewController? controller;
  bool ready = false;
  String documentName = 'Sem título.docx';
  bool dirty = false;

  Stream<Map<String, dynamic>> get events => _events.stream;

  void setBackgroundAttached(bool value) {
    if (backgroundAttached.value != value) {
      backgroundAttached.value = value;
    }
  }

  void registerController(InAppWebViewController value) {
    controller = value;
    final id = identityHashCode(value);
    if (_registeredControllers.contains(id)) return;
    _registeredControllers.add(id);

    value.addJavaScriptHandler(
      handlerName: 'LexPdfOfficeEvent',
      callback: (args) {
        if (args.isEmpty) return <String, Object?>{'ok': true};
        final raw = args.first;
        if (raw is Map) {
          final event = raw.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          _ingest(event);
        }
        return <String, Object?>{'ok': true};
      },
    );
  }

  void _ingest(Map<String, dynamic> event) {
    final type = event['type'];
    final name = event['name'];

    if (name is String && name.isNotEmpty) {
      documentName = name;
    }
    if (type == 'ready') {
      ready = true;
      dirty = false;
    } else if (type == 'documentOpened' || type == 'documentSaved') {
      dirty = false;
    } else if (type == 'documentChanged') {
      dirty = true;
    }

    if (!_events.isClosed) {
      _events.add(event);
    }
  }
}

/// Mantém o runtime Office aquecido na home usando a mesma WebView que será
/// reapresentada na tela do editor.
///
/// Antes de navegar para o editor, [backgroundAttached] é desligado por um
/// frame. Assim nunca existem duas InAppWebViews ativas com o mesmo token.
class OfficeRuntimePrewarmer extends StatelessWidget {
  const OfficeRuntimePrewarmer({super.key});

  bool get _supported => Platform.isAndroid || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();

    final runtime = OfficeWebViewRuntime.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: runtime.backgroundAttached,
      builder: (context, attached, child) {
        if (!attached) return const SizedBox.shrink();

        return IgnorePointer(
          child: Opacity(
            opacity: 0.001,
            child: SizedBox.square(
              dimension: 1,
              child: InAppWebView(
                keepAlive: runtime.keepAlive,
                initialFile: 'assets/office_runtime/index.html',
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: true,
                  transparentBackground: false,
                ),
                onWebViewCreated: runtime.registerController,
                onLoadStop: (controller, url) async {
                  runtime.registerController(controller);
                  try {
                    await controller.evaluateJavascript(
                      source:
                          'window.LexPdfOffice?.warmEngine?.().catch?.(() => {})',
                    );
                  } catch (_) {
                    // Prewarm é oportunista e nunca deve bloquear o app.
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
