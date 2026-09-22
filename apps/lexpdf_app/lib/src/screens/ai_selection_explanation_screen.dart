import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai/ai_models.dart';
import '../core/ai/remote_ai_engine.dart';
import '../core/annotations/pdf_annotation_object.dart';
import '../core/backend/backend_config.dart';
import '../core/storage/local_advanced_study_store.dart';
import '../core/storage/local_study_notebook_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import '../widgets/flashcard_organization_fields.dart';

class AiSelectionExplanationScreen extends StatefulWidget {
  const AiSelectionExplanationScreen({
    required this.selectedText,
    required this.studyStore,
    required this.annotations,
    required this.sourceDocumentId,
    required this.sourceDocumentTitle,
    required this.sourcePage,
    required this.anchorX,
    required this.anchorY,
    this.onAnnotationSaved,
    super.key,
  });

  final String selectedText;
  final LocalStudyNotebookStore studyStore;
  final LocalTextAnnotationStore annotations;
  final String sourceDocumentId;
  final String sourceDocumentTitle;
  final int sourcePage;
  final double anchorX;
  final double anchorY;
  final VoidCallback? onAnnotationSaved;

  @override
  State<AiSelectionExplanationScreen> createState() =>
      _AiSelectionExplanationScreenState();
}

class _AiSelectionExplanationScreenState
    extends State<AiSelectionExplanationScreen> {
  AiExplanationDepth _depth = AiExplanationDepth.detailed;
  AiExplanationIntent _intent = AiExplanationIntent.explain;
  AiStudyResult? _result;
  Object? _error;
  bool _loading = false;
  bool _saving = false;

  Future<RemoteAiStudyEngine> _engine() async {
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
    return RemoteAiStudyEngine(
      endpoint: Uri.parse(config.aiGatewayUrl),
      bearerToken: token,
    );
  }

  Future<AiStudyResult?> _request(
    AiExplanationDepth depth, {
    AiExplanationIntent intent = AiExplanationIntent.explain,
    bool replaceResult = true,
  }) async {
    if (_loading) return null;
    setState(() {
      _depth = depth;
      _intent = intent;
      _loading = true;
      _error = null;
    });
    try {
      final engine = await _engine();
      final result = await engine.runExplanation(
        action: AiStudyAction.explain,
        text: widget.selectedText,
        explanationDepth: depth,
        intent: intent,
      );
      if (mounted && replaceResult) setState(() => _result = result);
      return result;
    } catch (error) {
      if (mounted) setState(() => _error = error);
      return null;
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

  Future<void> _saveToNotebook() async {
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

  Future<void> _saveAsAnnotation() async {
    final text = _result?.text?.trim();
    if (text == null || text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final payload = jsonEncode({
        'text': text,
        'sourceText': widget.selectedText,
        'bold': false,
        'italic': false,
        'underline': false,
        'fontSize': 16.0,
        'fontFamily': 'Roboto',
        'textAlign': 'left',
      });
      final encoded =
          'lexpdf-note-v1:${base64Url.encode(utf8.encode(payload))}';
      final now = DateTime.now().toUtc();
      await widget.annotations.objectStore.upsert(
        PdfAnnotationObject(
          id: 'ai-note-${now.microsecondsSinceEpoch.toRadixString(36)}',
          documentId: widget.sourceDocumentId,
          pageNumber: widget.sourcePage,
          type: PdfAnnotationObjectType.note,
          x: widget.anchorX,
          y: widget.anchorY,
          width: 0.03,
          height: 0.03,
          colorValue: 0xFF315A7D,
          fillColorValue: 0xFF90CAF9,
          opacity: 1.0,
          strokeWidth: 1.2,
          textValue: encoded,
          createdAt: now,
          updatedAt: now,
        ),
      );
      widget.onAnnotationSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Explicação salva como anotação no PDF.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _suggestFlashcard() async {
    final result = await _request(
      AiExplanationDepth.detailed,
      intent: AiExplanationIntent.flashcard,
      replaceResult: false,
    );
    if (!mounted || result == null) return;
    final suggestion = result.flashcards.isEmpty ? null : result.flashcards.first;
    if (suggestion == null) {
      setState(() {
        _error = StateError(
          'A IA não retornou um flashcard válido. Tente novamente.',
        );
      });
      return;
    }

    final edited = await _editFlashcard(suggestion);
    if (!mounted || edited == null) return;
    if (edited.question.trim().isEmpty || edited.answer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha pergunta e resposta.')),
      );
      return;
    }

    await widget.studyStore.saveResult(
      documentId: widget.sourceDocumentId,
      documentTitle: widget.sourceDocumentTitle,
      sourcePage: widget.sourcePage,
      subject: edited.subject,
      topic: edited.topic,
      result: AiStudyResult(
        action: AiStudyAction.flashcards,
        engine: AiEngineKind.remote,
        sourceText: widget.selectedText,
        flashcards: [
          AiFlashcard(
            question: edited.question.trim(),
            answer: edited.answer.trim(),
          ),
        ],
        model: result.model,
        fallbackUsed: result.fallbackUsed,
        quotaRemaining: result.quotaRemaining,
        quotaLimit: result.quotaLimit,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 4),
          content: Text(
            'Flashcard revisado e salvo. Acesse-o em Flashcards na tela inicial.',
          ),
        ),
      );
    }
  }

  Future<_AiFlashcardDraft?> _editFlashcard(
    AiFlashcard suggestion,
  ) async {
    final question = TextEditingController(text: suggestion.question);
    final answer = TextEditingController(text: suggestion.answer);
    final subject = TextEditingController();
    final topic = TextEditingController();
    final catalog = FlashcardOrganizationCatalog.fromEntries(
      await LocalAdvancedStudyStore(widget.studyStore.db).listFlashcardEntries(
        limit: 20000,
      ),
    );
    if (!mounted) {
      question.dispose();
      answer.dispose();
      subject.dispose();
      topic.dispose();
      return null;
    }

    try {
      return await showDialog<_AiFlashcardDraft>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Revisar flashcard sugerido'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'A IA apenas sugere. Edite livremente antes de salvar.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: question,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Pergunta',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: answer,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Resposta',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 10),
                  FlashcardOrganizationFields(
                    subjectController: subject,
                    topicController: topic,
                    catalog: catalog,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _AiFlashcardDraft(
                  question: question.text,
                  answer: answer.text,
                  subject: subject.text.trim(),
                  topic: topic.text.trim(),
                ),
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        ),
      );
    } finally {
      question.dispose();
      answer.dispose();
      subject.dispose();
      topic.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente de IA do trecho')),
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
                    'Trecho selecionado · página ${widget.sourcePage}',
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
            'Como você quer que a IA trabalhe este trecho?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ModeButton(
                label: 'Rápida',
                icon: Icons.bolt_outlined,
                selected: _intent == AiExplanationIntent.explain &&
                    _depth == AiExplanationDepth.quick,
                enabled: !_loading,
                onPressed: () => unawaited(
                  _request(AiExplanationDepth.quick),
                ),
              ),
              _ModeButton(
                label: 'Detalhada',
                icon: Icons.subject_outlined,
                selected: _intent == AiExplanationIntent.explain &&
                    _depth == AiExplanationDepth.detailed,
                enabled: !_loading,
                onPressed: () => unawaited(
                  _request(AiExplanationDepth.detailed),
                ),
              ),
              _ModeButton(
                label: 'Aprofundada',
                icon: Icons.psychology_alt_outlined,
                selected: _intent == AiExplanationIntent.explain &&
                    _depth == AiExplanationDepth.deep,
                enabled: !_loading,
                onPressed: () => unawaited(
                  _request(AiExplanationDepth.deep),
                ),
              ),
              _ModeButton(
                label: 'Modo Concurso',
                icon: Icons.school_outlined,
                selected: _intent == AiExplanationIntent.contest,
                enabled: !_loading,
                onPressed: () => unawaited(
                  _request(
                    AiExplanationDepth.detailed,
                    intent: AiExplanationIntent.contest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'O documento continua sendo a fonte primária. A IA separa explicação do texto e informação complementar e pode errar; confirme conteúdo jurídico ou técnico crítico na fonte oficial.',
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
                title: const Text('Não foi possível concluir a ação'),
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
                            _intent.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (result!.fallbackUsed)
                          const Tooltip(
                            message:
                                'O modelo alternativo foi usado automaticamente.',
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
                        'Saldo de IA hoje: ${result.quotaRemaining} créditos'
                        '${result.quotaLimit == null ? '' : ' de ${result.quotaLimit}'}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => unawaited(
                                    _request(
                                      AiExplanationDepth.quick,
                                      intent: AiExplanationIntent.simplify,
                                    ),
                                  ),
                          icon: const Icon(Icons.lightbulb_outline),
                          label: const Text('Simplificar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => unawaited(
                                    _request(AiExplanationDepth.deep),
                                  ),
                          icon: const Icon(Icons.zoom_in_outlined),
                          label: const Text('Aprofundar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => unawaited(
                                    _request(
                                      AiExplanationDepth.detailed,
                                      intent: AiExplanationIntent.example,
                                    ),
                                  ),
                          icon: const Icon(Icons.tips_and_updates_outlined),
                          label: const Text('Dar exemplo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _suggestFlashcard,
                          icon: const Icon(Icons.style_outlined),
                          label: const Text('Sugerir flashcard'),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copiar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _saveAsAnnotation,
                          icon: const Icon(Icons.push_pin_outlined),
                          label: const Text('Salvar como anotação'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _saveToNotebook,
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

class _AiFlashcardDraft {
  const _AiFlashcardDraft({
    required this.question,
    required this.answer,
    required this.subject,
    required this.topic,
  });

  final String question;
  final String answer;
  final String subject;
  final String topic;
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
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
