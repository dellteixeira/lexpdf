import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai/ai_models.dart';
import '../core/ai/remote_ai_engine.dart';
import '../core/backend/backend_config.dart';
import '../core/storage/local_study_notebook_store.dart';

class AiSelectionExplanationScreen extends StatefulWidget {
  const AiSelectionExplanationScreen({
    required this.selectedText,
    required this.studyStore,
    required this.sourceDocumentId,
    required this.sourceDocumentTitle,
    required this.sourcePage,
    super.key,
  });

  final String selectedText;
  final LocalStudyNotebookStore studyStore;
  final String sourceDocumentId;
  final String sourceDocumentTitle;
  final int sourcePage;

  @override
  State<AiSelectionExplanationScreen> createState() =>
      _AiSelectionExplanationScreenState();
}

class _AiSelectionExplanationScreenState
    extends State<AiSelectionExplanationScreen> {
  AiExplanationDepth _depth = AiExplanationDepth.detailed;
  AiStudyResult? _result;
  Object? _error;
  bool _loading = false;
  bool _saving = false;

  Future<void> _explain(AiExplanationDepth depth) async {
    if (_loading) return;
    setState(() {
      _depth = depth;
      _loading = true;
      _error = null;
    });
    try {
      const config = BackendConfig.fromEnvironment;
      if (!config.hasAiGateway) {
        throw StateError('O gateway de IA não está configurado neste build.');
      }
      if (!config.hasSupabase) {
        throw StateError('A autenticação LexPDF não está configurada.');
      }
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null || token.trim().isEmpty) {
        throw StateError('Entre na sua conta LexPDF para usar a IA online.');
      }
      final result = await RemoteAiStudyEngine(
        endpoint: Uri.parse(config.aiGatewayUrl),
        bearerToken: token,
      ).run(
        action: AiStudyAction.explain,
        text: widget.selectedText,
        explanationDepth: depth,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final text = _result?.text?.trim();
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Explicação copiada.')),
      );
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.studyStore.saveResult(
        documentId: widget.sourceDocumentId,
        documentTitle: widget.sourceDocumentTitle,
        result: result,
        sourcePage: widget.sourcePage,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Explicação salva no caderno de estudo.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Explicar com IA')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trecho selecionado',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(widget.selectedText),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Profundidade da explicação',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DepthButton(
                label: 'Rápida',
                icon: Icons.bolt_outlined,
                selected: _depth == AiExplanationDepth.quick,
                enabled: !_loading,
                onPressed: () => unawaited(_explain(AiExplanationDepth.quick)),
              ),
              _DepthButton(
                label: 'Detalhada',
                icon: Icons.subject_outlined,
                selected: _depth == AiExplanationDepth.detailed,
                enabled: !_loading,
                onPressed: () =>
                    unawaited(_explain(AiExplanationDepth.detailed)),
              ),
              _DepthButton(
                label: 'Aprofundada',
                icon: Icons.psychology_alt_outlined,
                selected: _depth == AiExplanationDepth.deep,
                enabled: !_loading,
                onPressed: () => unawaited(_explain(AiExplanationDepth.deep)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'A IA explica o trecho e separa o que está apoiado pelo texto de informações complementares. Respostas de IA podem conter erros; confirme informações jurídicas ou técnicas críticas na fonte oficial.',
          ),
          if (_loading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Não foi possível gerar a explicação'),
                subtitle: Text('$_error'),
              ),
            ),
          ],
          if (result?.text?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            result!.explanationDepth?.label ?? 'Explicação',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (result.fallbackUsed)
                          const Tooltip(
                            message: 'O modelo alternativo foi usado automaticamente.',
                            child: Icon(Icons.swap_horiz, size: 20),
                          ),
                      ],
                    ),
                    if (result.model?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Modelo: ${result.model}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 14),
                    SelectableText(result.text!),
                    if (result.quotaRemaining != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Saldo de IA hoje: ${result.quotaRemaining} créditos${result.quotaLimit == null ? '' : ' de ${result.quotaLimit}'}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copiar'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Salvar no caderno'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DepthButton extends StatelessWidget {
  const _DepthButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon),
            label: Text(label),
          );
  }
}
