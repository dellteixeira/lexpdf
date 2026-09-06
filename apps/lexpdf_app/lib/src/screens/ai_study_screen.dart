import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ai/ai_engine.dart';
import '../core/ai/ai_models.dart';
import '../core/ai/local_study_engine.dart';
import '../core/ai/pdf_ai_text_service.dart';
import '../core/ai/remote_ai_engine.dart';
import '../core/backend/backend_config.dart';

class AiStudyScreen extends StatefulWidget {
  const AiStudyScreen({
    this.initialText,
    this.documentPath,
    this.title = 'Estudo assistido',
    super.key,
  });

  final String? initialText;
  final String? documentPath;
  final String title;

  @override
  State<AiStudyScreen> createState() => _AiStudyScreenState();
}

class _AiStudyScreenState extends State<AiStudyScreen> {
  final TextEditingController _textController = TextEditingController();
  final LocalStudyEngine _local = const LocalStudyEngine();
  final PdfAiTextService _textService = const PdfAiTextService();
  AiEngineKind _engineKind = AiEngineKind.local;
  AiStudyResult? _result;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _textController.text = widget.initialText?.trim() ?? '';
    if (_textController.text.isEmpty && widget.documentPath != null) {
      unawaited(_loadDocumentText());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentText() async {
    final path = widget.documentPath;
    if (path == null) return;
    setState(() => _loading = true);
    try {
      final text = await _textService.extractDocumentText(path);
      if (!mounted) return;
      _textController.text = text;
      if (text.isEmpty) {
        setState(() => _error = StateError('Nenhum texto incorporado foi encontrado. Use OCR antes desta ação.'));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AiStudyEngine _engine() {
    if (_engineKind == AiEngineKind.local) return _local;
    const config = BackendConfig.fromEnvironment;
    if (!config.hasAiGateway) {
      throw StateError('Nenhum gateway de IA foi configurado.');
    }
    return RemoteAiStudyEngine(endpoint: Uri.parse(config.aiGatewayUrl));
  }

  Future<void> _run(AiStudyAction action) async {
    final text = _textController.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _engine().run(action: action, text: text, itemCount: 8);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const config = BackendConfig.fromEnvironment;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Fonte',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      SegmentedButton<AiEngineKind>(
                        segments: [
                          const ButtonSegment(
                            value: AiEngineKind.local,
                            icon: Icon(Icons.offline_bolt_outlined),
                            label: Text('Local'),
                          ),
                          ButtonSegment(
                            value: AiEngineKind.remote,
                            enabled: config.hasAiGateway,
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: const Text('IA online'),
                          ),
                        ],
                        selected: {_engineKind},
                        onSelectionChanged: _loading
                            ? null
                            : (value) => setState(() => _engineKind = value.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _engineKind == AiEngineKind.local
                        ? 'Processamento determinístico e offline; nenhum texto sai do dispositivo.'
                        : 'O texto será enviado ao gateway de IA configurado pelo usuário.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    minLines: 6,
                    maxLines: 14,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Texto de estudo',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : () => _run(AiStudyAction.explain),
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('Explicar'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : () => _run(AiStudyAction.summarize),
                        icon: const Icon(Icons.summarize_outlined),
                        label: const Text('Resumir'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : () => _run(AiStudyAction.flashcards),
                        icon: const Icon(Icons.style_outlined),
                        label: const Text('Flashcards'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : () => _run(AiStudyAction.questions),
                        icon: const Icon(Icons.quiz_outlined),
                        label: const Text('Perguntas'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Não foi possível concluir a ação'),
                subtitle: Text('$_error'),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            _ResultView(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});

  final AiStudyResult result;

  @override
  Widget build(BuildContext context) {
    final engine = result.engine == AiEngineKind.local ? 'Local/offline' : 'IA online';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Resultado', style: Theme.of(context).textTheme.titleLarge),
                ),
                Chip(label: Text(engine)),
              ],
            ),
            if (result.text?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              SelectableText(result.text!),
            ],
            if (result.flashcards.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var index = 0; index < result.flashcards.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(result.flashcards[index].question),
                  subtitle: Text(result.flashcards[index].answer),
                ),
            ],
            if (result.questions.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var index = 0; index < result.questions.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(result.questions[index]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
