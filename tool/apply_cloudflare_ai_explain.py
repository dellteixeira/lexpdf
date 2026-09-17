from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)

# --- AI model contract -----------------------------------------------------
write(
    "apps/lexpdf_app/lib/src/core/ai/ai_models.dart",
    '''enum AiStudyAction { explain, summarize, flashcards, questions }

enum AiEngineKind { local, remote }

enum AiExplanationDepth { quick, detailed, deep }

extension AiExplanationDepthLabel on AiExplanationDepth {
  String get label => switch (this) {
        AiExplanationDepth.quick => 'Rápida',
        AiExplanationDepth.detailed => 'Detalhada',
        AiExplanationDepth.deep => 'Aprofundada',
      };
}

class AiFlashcard {
  const AiFlashcard({required this.question, required this.answer});

  final String question;
  final String answer;
}

class AiStudyResult {
  const AiStudyResult({
    required this.action,
    required this.engine,
    required this.sourceText,
    this.text,
    this.flashcards = const [],
    this.questions = const [],
    this.explanationDepth,
    this.model,
    this.fallbackUsed = false,
    this.quotaRemaining,
    this.quotaLimit,
  });

  final AiStudyAction action;
  final AiEngineKind engine;
  final String sourceText;
  final String? text;
  final List<AiFlashcard> flashcards;
  final List<String> questions;
  final AiExplanationDepth? explanationDepth;
  final String? model;
  final bool fallbackUsed;
  final int? quotaRemaining;
  final int? quotaLimit;
}
''',
)

write(
    "apps/lexpdf_app/lib/src/core/ai/ai_engine.dart",
    '''import 'ai_models.dart';

abstract interface class AiStudyEngine {
  AiEngineKind get kind;

  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
    AiExplanationDepth explanationDepth = AiExplanationDepth.detailed,
  });
}
''',
)

# Local engines accept the richer interface but keep their deterministic behavior.
for path in [
    "apps/lexpdf_app/lib/src/core/ai/local_study_engine.dart",
    "apps/lexpdf_app/lib/src/core/ai/local_model_ai_engine.dart",
]:
    text = read(path)
    old = """    int itemCount = 8,\n  }) async {"""
    new = """    int itemCount = 8,\n    AiExplanationDepth explanationDepth = AiExplanationDepth.detailed,\n  }) async {"""
    text = replace_once(text, old, new, f"{path} run signature")
    write(path, text)

# Remote engine: depth + authenticated gateway metadata.
write(
    "apps/lexpdf_app/lib/src/core/ai/remote_ai_engine.dart",
    '''import 'dart:convert';
import 'dart:io';

import 'ai_engine.dart';
import 'ai_input_policy.dart';
import 'ai_models.dart';

class RemoteAiStudyEngine implements AiStudyEngine {
  RemoteAiStudyEngine({
    required Uri endpoint,
    this.bearerToken,
    this.inputPolicy = const AiInputPolicy(maxCharacters: 12000),
    HttpClient? httpClient,
  })  : endpoint = _validatedEndpoint(endpoint),
        _http = httpClient ?? HttpClient();

  final Uri endpoint;
  final String? bearerToken;
  final AiInputPolicy inputPolicy;
  final HttpClient _http;

  static Uri _validatedEndpoint(Uri endpoint) {
    if (endpoint.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote AI endpoints must use HTTPS.',
      );
    }
    if (endpoint.host.trim().isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote AI endpoint must include a host.',
      );
    }
    if (endpoint.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Remote AI endpoint must not embed credentials in the URL.',
      );
    }
    return endpoint;
  }

  @override
  AiEngineKind get kind => AiEngineKind.remote;

  @override
  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
    AiExplanationDepth explanationDepth = AiExplanationDepth.detailed,
  }) async {
    final input = inputPolicy.prepare(text, itemCount);
    final request = await _http.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(jsonEncode({
      'action': action.name,
      'text': input.text,
      'itemCount': input.itemCount,
      'depth': explanationDepth.name,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw StateError('Entre na sua conta LexPDF para usar a IA online.');
      }
      if (response.statusCode == 429) {
        throw StateError(
          'Limite temporário da IA atingido. Aguarde um pouco ou tente novamente amanhã.',
        );
      }
      throw HttpException('${response.statusCode}: $body', uri: endpoint);
    }
    final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
    final quota = decoded['quota'] is Map
        ? (decoded['quota'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return AiStudyResult(
      action: action,
      engine: kind,
      sourceText: input.text,
      text: decoded['text']?.toString(),
      explanationDepth: explanationDepth,
      model: decoded['model']?.toString(),
      fallbackUsed: decoded['fallbackUsed'] == true,
      quotaRemaining: _asInt(quota['creditsRemaining']),
      quotaLimit: _asInt(quota['dailyCreditLimit']),
      flashcards: ((decoded['flashcards'] as List?) ?? const [])
          .map((item) {
            final map = (item as Map).cast<String, dynamic>();
            return AiFlashcard(
              question: map['question']?.toString() ?? '',
              answer: map['answer']?.toString() ?? '',
            );
          })
          .where((item) => item.question.isNotEmpty || item.answer.isNotEmpty)
          .take(input.itemCount)
          .toList(growable: false),
      questions: ((decoded['questions'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .take(input.itemCount)
          .toList(growable: false),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
''',
)

# Production endpoint defaults safely even when release workflows pass an empty dart-define.
path = "apps/lexpdf_app/lib/src/core/backend/backend_config.dart"
text = read(path)
text = replace_once(
    text,
    """  static const fromEnvironment = BackendConfig(\n""",
    """  static const _configuredAiGatewayUrl = String.fromEnvironment(\n    'LEXPDF_AI_GATEWAY_URL',\n  );\n\n  static const fromEnvironment = BackendConfig(\n""",
    "backend ai gateway const",
)
text = replace_once(
    text,
    """    aiGatewayUrl: String.fromEnvironment('LEXPDF_AI_GATEWAY_URL'),\n""",
    """    aiGatewayUrl: _configuredAiGatewayUrl.isNotEmpty\n        ? _configuredAiGatewayUrl\n        : (_isProduction\n            ? 'https://lexpdf-api.d3-concursos.workers.dev/v1/ai/explain'\n            : ''),\n""",
    "backend ai gateway default",
)
write(path, text)

# Dedicated selection explanation screen; flashcards remain manual elsewhere.
write(
    "apps/lexpdf_app/lib/src/screens/ai_selection_explanation_screen.dart",
    '''import 'dart:async';

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
''',
)

# Selection menu: add explicit AI action without restoring the removed generic Explain/Question actions.
path = "apps/lexpdf_app/lib/src/widgets/pdf_selection_action_menu.dart"
text = read(path)
anchor = """      ContextMenuButtonItem(\n        label: 'Flashcard',\n        onPressed: () {\n          params.dismissContextMenu();\n          unawaited(_createManualFlashcard(context, delegate));\n        },\n      ),\n"""
addition = anchor + """      if (onStudyAction != null)\n        ContextMenuButtonItem(\n          label: 'Explicar com IA',\n          onPressed: () {\n            params.dismissContextMenu();\n            unawaited(_explainSelectionWithAi(context, delegate));\n          },\n        ),\n"""
text = replace_once(text, anchor, addition, "selection AI action")
helper_anchor = """  Future<void> _createManualFlashcard(\n"""
helper = """  Future<void> _explainSelectionWithAi(\n    BuildContext context,\n    PdfTextSelectionDelegate delegate,\n  ) async {\n    final callback = onStudyAction;\n    if (callback == null) return;\n    final ranges = await delegate.getSelectedTextRanges();\n    if (ranges.isEmpty) return;\n    final selectedText = _selectionText(ranges);\n    if (selectedText.isEmpty) return;\n    await delegate.clearTextSelection();\n    if (!context.mounted) return;\n    await callback(context, selectedText, AiStudyAction.explain);\n  }\n\n""" + helper_anchor
text = replace_once(text, helper_anchor, helper, "selection AI helper")
write(path, text)

# Wire the unified PDF workspace selection to the dedicated remote-AI screen.
path = "apps/lexpdf_app/lib/src/screens/pdf_workspace_stylus_screen.dart"
text = read(path)
text = replace_once(
    text,
    """import '../core/storage/local_pdf_navigation_store.dart';\nimport '../core/storage/local_text_annotation_store.dart';\n""",
    """import '../core/storage/local_pdf_navigation_store.dart';\nimport '../core/storage/local_study_notebook_store.dart';\nimport '../core/storage/local_text_annotation_store.dart';\n""",
    "stylus study store import",
)
text = replace_once(
    text,
    """import 'pdf_export_screen.dart';\n""",
    """import 'ai_selection_explanation_screen.dart';\nimport 'pdf_export_screen.dart';\n""",
    "stylus AI screen import",
)
old = """    onChanged: () {\n      if (!mounted) return;\n      setState(() => _annotationRevision++);\n      _controller.invalidate();\n    },\n  );\n"""
new = """    onChanged: () {\n      if (!mounted) return;\n      setState(() => _annotationRevision++);\n      _controller.invalidate();\n    },\n    onStudyAction: (context, selectedText, action) async {\n      if (action.name != 'explain') return;\n      await Navigator.of(context).push(\n        MaterialPageRoute<void>(\n          builder: (_) => AiSelectionExplanationScreen(\n            selectedText: selectedText,\n            studyStore: LocalStudyNotebookStore(widget.store.db),\n            sourceDocumentId: widget.document.id,\n            sourceDocumentTitle: widget.document.name,\n            sourcePage: _page,\n          ),\n        ),\n      );\n    },\n  );\n"""
text = replace_once(text, old, new, "stylus selection callback")
write(path, text)

# Fix the now-stale study help copy in the multi-tab shell.
path = "apps/lexpdf_app/lib/src/screens/pdf_workspace_screen.dart"
text = read(path)
text = replace_once(
    text,
    """          'Selecione um trecho dentro do PDF para acessar Destacar, Anotar, '\n          'Flashcard, Questão e Explicar. O material gerado permanece ligado '\n          'ao fluxo local de cadernos do LexPDF.',\n""",
    """          'Selecione um trecho dentro do PDF para acessar Destacar, Anotar, '\n          'Flashcard manual e Explicar com IA. A explicação online oferece os '\n          'níveis Rápida, Detalhada e Aprofundada e exige uma conta LexPDF.',\n""",
    "study help copy",
)
write(path, text)

# --- Cloudflare Workers AI backend ---------------------------------------
path = "backend/cloudflare/src/index.ts"
text = read(path)
text = replace_once(
    text,
    """  MAX_UPLOAD_BYTES?: string;\n  DOCUMENTS: R2Bucket;\n""",
    """  MAX_UPLOAD_BYTES?: string;\n  AI_DAILY_CREDIT_LIMIT?: string;\n  AI_RATE_LIMIT_PER_MINUTE?: string;\n  AI_MAX_INPUT_CHARS?: string;\n  AI_QUICK_MODEL?: string;\n  AI_DEEP_MODEL?: string;\n  AI: Ai;\n  DOCUMENTS: R2Bucket;\n""",
    "worker Env AI binding",
)
text = replace_once(
    text,
    """const MAX_LIST_LIMIT = 1000;\n""",
    """const MAX_LIST_LIMIT = 1000;\nconst DEFAULT_AI_DAILY_CREDIT_LIMIT = 240;\nconst DEFAULT_AI_RATE_LIMIT_PER_MINUTE = 12;\nconst DEFAULT_AI_MAX_INPUT_CHARS = 12000;\nconst DEFAULT_AI_QUICK_MODEL = '@cf/zai-org/glm-4.7-flash';\nconst DEFAULT_AI_DEEP_MODEL = '@cf/google/gemma-4-26b-a4b-it';\n\ntype AiExplanationDepth = 'quick' | 'detailed' | 'deep';\n\ntype AiQuotaResult = {\n  allowed: boolean;\n  reason: string;\n  creditsUsed: number;\n  creditsRemaining: number;\n  requests: number;\n};\n""",
    "worker AI constants",
)
route_anchor = """  if (url.pathname === \"/health\") {\n    return json({ service: \"lexpdf-api\", status: \"ok\", environment: env.ENVIRONMENT ?? \"unknown\", r2: Boolean(env.DOCUMENTS), queue: Boolean(env.SYNC_QUEUE) }, 200, requestId);\n  }\n  if (!url.pathname.startsWith(\"/v1/cloud/\")) return json({ error: \"not_found\" }, 404, requestId);\n\n  const user = await authenticate(request, env);\n"""
route_replacement = """  if (url.pathname === \"/health\") {\n    return json({ service: \"lexpdf-api\", status: \"ok\", environment: env.ENVIRONMENT ?? \"unknown\", r2: Boolean(env.DOCUMENTS), queue: Boolean(env.SYNC_QUEUE), ai: Boolean(env.AI) }, 200, requestId);\n  }\n\n  if (url.pathname === \"/v1/ai/explain\") {\n    return handleAiExplain(request, env, requestId);\n  }\n\n  if (!url.pathname.startsWith(\"/v1/cloud/\")) return json({ error: \"not_found\" }, 404, requestId);\n\n  const user = await authenticate(request, env);\n"""
text = replace_once(text, route_anchor, route_replacement, "worker AI route")
functions_anchor = """async function authenticate(request: Request, env: Env): Promise<AuthUser | null> {\n"""
functions = r'''async function handleAiExplain(request: Request, env: Env, requestId: string): Promise<Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, requestId);
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) return json({ error: "unsupported_media_type" }, 415, requestId);

  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401, requestId);
  if (!env.AI) return json({ error: "ai_not_configured" }, 503, requestId);

  let body: { action?: string; text?: string; depth?: string };
  try {
    body = (await request.json()) as { action?: string; text?: string; depth?: string };
  } catch {
    return json({ error: "invalid_json" }, 400, requestId);
  }
  if (body.action != null && body.action !== "explain") {
    return json({ error: "unsupported_ai_action" }, 400, requestId);
  }

  const maxInputChars = parsePositiveInt(env.AI_MAX_INPUT_CHARS) ?? DEFAULT_AI_MAX_INPUT_CHARS;
  const sourceText = (body.text ?? "").trim();
  if (!sourceText) return json({ error: "empty_text" }, 400, requestId);
  if (sourceText.length > maxInputChars) {
    return json({ error: "text_too_large", maxCharacters: maxInputChars }, 413, requestId);
  }

  const depth = normalizeAiDepth(body.depth);
  const creditCost = aiCreditCost(depth);
  const dailyLimit = parsePositiveInt(env.AI_DAILY_CREDIT_LIMIT) ?? DEFAULT_AI_DAILY_CREDIT_LIMIT;
  const minuteLimit = parsePositiveInt(env.AI_RATE_LIMIT_PER_MINUTE) ?? DEFAULT_AI_RATE_LIMIT_PER_MINUTE;
  const quota = await consumeAiQuota(env, user.id, creditCost, dailyLimit, minuteLimit);
  if (!quota.allowed) {
    return json({
      error: quota.reason === "rate_limit" ? "ai_rate_limit" : "ai_daily_limit",
      quota: { ...quota, dailyCreditLimit: dailyLimit, creditCost },
    }, 429, requestId);
  }

  const quickModel = env.AI_QUICK_MODEL?.trim() || DEFAULT_AI_QUICK_MODEL;
  const deepModel = env.AI_DEEP_MODEL?.trim() || DEFAULT_AI_DEEP_MODEL;
  const primaryModel = depth === "quick" ? quickModel : deepModel;
  const fallbackModel = primaryModel === quickModel ? deepModel : quickModel;
  const systemPrompt = aiSystemPrompt(depth);
  const input = {
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: `TRECHO SELECIONADO:\n${sourceText}` },
    ],
    max_tokens: aiMaxTokens(depth),
    temperature: 0.2,
    stream: false,
  };

  let model = primaryModel;
  let fallbackUsed = false;
  let text: string;
  try {
    text = await runAiText(env, primaryModel, input);
  } catch (primaryError) {
    console.warn("lexpdf_ai_primary_failed", { requestId, model: primaryModel, error: String(primaryError) });
    model = fallbackModel;
    fallbackUsed = true;
    try {
      text = await runAiText(env, fallbackModel, input);
    } catch (fallbackError) {
      console.error("lexpdf_ai_fallback_failed", { requestId, model: fallbackModel, error: String(fallbackError) });
      return json({ error: "ai_provider_unavailable", requestId }, 502, requestId);
    }
  }

  return json({
    text,
    depth,
    model,
    fallbackUsed,
    quota: {
      creditsUsed: quota.creditsUsed,
      creditsRemaining: quota.creditsRemaining,
      dailyCreditLimit: dailyLimit,
      creditCost,
      requests: quota.requests,
    },
  }, 200, requestId);
}

function normalizeAiDepth(value?: string): AiExplanationDepth {
  if (value === "quick" || value === "deep") return value;
  return "detailed";
}

function aiCreditCost(depth: AiExplanationDepth): number {
  if (depth === "quick") return 1;
  if (depth === "deep") return 4;
  return 2;
}

function aiMaxTokens(depth: AiExplanationDepth): number {
  if (depth === "quick") return 350;
  if (depth === "deep") return 1400;
  return 800;
}

function aiSystemPrompt(depth: AiExplanationDepth): string {
  const detail = depth === "quick"
    ? "Seja conciso: explique a ideia central em poucos parágrafos."
    : depth === "deep"
      ? "Seja aprofundado: decomponha conceitos, condições, relações, consequências, ambiguidades e dê um exemplo quando ele puder ser formulado com segurança."
      : "Seja detalhado: explique conceitos, relações entre ideias e dê um exemplo curto quando apropriado.";
  return [
    "Você é o explicador de trechos do LexPDF. Responda em português do Brasil.",
    detail,
    "Use o trecho fornecido como fonte primária. Não invente fatos, artigos, precedentes, datas ou jurisprudência.",
    "Quando acrescentar conhecimento que não está literalmente no trecho, coloque-o em uma seção chamada 'Informação complementar' e deixe claro que é externo ao texto selecionado.",
    "Se o trecho for jurídico, não afirme que uma lei, súmula ou jurisprudência está vigente/atualizada sem que isso esteja no próprio trecho.",
    "Se houver ambiguidade ou contexto insuficiente, diga explicitamente qual informação falta.",
    "Estruture a resposta, quando aplicável, em: 'Explicação do trecho', 'Em termos simples', 'Exemplo prático' e 'Informação complementar / limitações'.",
    "Não apresente porcentagens de confiança inventadas.",
  ].join("\n");
}

async function runAiText(env: Env, model: string, input: Record<string, unknown>): Promise<string> {
  const output = await env.AI.run(model as any, input as any) as any;
  const candidate = typeof output?.response === "string"
    ? output.response
    : typeof output?.result?.response === "string"
      ? output.result.response
      : typeof output?.choices?.[0]?.message?.content === "string"
        ? output.choices[0].message.content
        : "";
  const text = candidate.trim();
  if (!text) throw new Error("AI provider returned an empty response.");
  return text;
}

async function consumeAiQuota(
  env: Env,
  userId: string,
  creditCost: number,
  dailyLimit: number,
  minuteLimit: number,
): Promise<AiQuotaResult> {
  const secret = env.SUPABASE_SECRET_KEY;
  if (!secret) throw new Error("SUPABASE_SECRET_KEY is required for AI quota enforcement.");
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/consume_ai_daily_quota`, {
    method: "POST",
    headers: {
      apikey: secret,
      authorization: `Bearer ${secret}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      p_user_id: userId,
      p_credit_cost: creditCost,
      p_daily_limit: dailyLimit,
      p_minute_limit: minuteLimit,
    }),
  });
  if (!response.ok) throw new Error(`AI quota RPC failed: ${response.status}`);
  const raw = await response.json() as any;
  const row = Array.isArray(raw) ? raw[0] : raw;
  if (!row) throw new Error("AI quota RPC returned no result.");
  return {
    allowed: row.allowed === true,
    reason: String(row.reason ?? "unknown"),
    creditsUsed: Number(row.credits_used ?? 0),
    creditsRemaining: Number(row.credits_remaining ?? 0),
    requests: Number(row.requests ?? 0),
  };
}

''' + functions_anchor
text = replace_once(text, functions_anchor, functions, "worker AI functions")
write(path, text)

# Worker binding and operational limits.
path = "backend/cloudflare/wrangler.toml"
text = read(path)
text = replace_once(
    text,
    """workers_dev = true\n\n# Runtime bindings. Secrets must be configured in Cloudflare and are never committed.\n""",
    """workers_dev = true\n\n[ai]\nbinding = \"AI\"\n\n# Runtime bindings. Secrets must be configured in Cloudflare and are never committed.\n""",
    "wrangler AI binding",
)
text = replace_once(
    text,
    """MAX_UPLOAD_BYTES = \"262144000\"\n""",
    """MAX_UPLOAD_BYTES = \"262144000\"\nAI_DAILY_CREDIT_LIMIT = \"240\"\nAI_RATE_LIMIT_PER_MINUTE = \"12\"\nAI_MAX_INPUT_CHARS = \"12000\"\nAI_QUICK_MODEL = \"@cf/zai-org/glm-4.7-flash\"\nAI_DEEP_MODEL = \"@cf/google/gemma-4-26b-a4b-it\"\n""",
    "wrangler AI vars",
)
write(path, text)

# Atomic daily quota + fixed one-minute window, service-role only.
write(
    "backend/supabase/migrations/20260917210000_add_ai_usage_quota.sql",
    r'''-- Server-side quota for the optional Workers AI explanation endpoint.
-- App clients cannot read or mutate this table/function directly.

create table if not exists public.ai_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null,
  credits_used integer not null default 0 check (credits_used >= 0),
  requests integer not null default 0 check (requests >= 0),
  rate_window_started_at timestamptz not null default now(),
  rate_window_requests integer not null default 0 check (rate_window_requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

create index if not exists ai_daily_usage_updated_idx
  on public.ai_daily_usage(updated_at desc);

alter table public.ai_daily_usage enable row level security;
revoke all on public.ai_daily_usage from public, anon, authenticated;
grant select, insert, update, delete on public.ai_daily_usage to service_role;

create or replace function public.consume_ai_daily_quota(
  p_user_id uuid,
  p_credit_cost integer,
  p_daily_limit integer,
  p_minute_limit integer default 12
)
returns table(
  allowed boolean,
  reason text,
  credits_used integer,
  credits_remaining integer,
  requests integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'utc')::date;
  v_used integer;
  v_requests integer;
  v_window_started timestamptz;
  v_window_requests integer;
begin
  if p_credit_cost < 1 or p_daily_limit < 1 or p_minute_limit < 1 then
    raise exception 'AI quota arguments must be positive';
  end if;

  insert into public.ai_daily_usage (user_id, usage_date)
  values (p_user_id, v_day)
  on conflict (user_id, usage_date) do nothing;

  select u.credits_used, u.requests, u.rate_window_started_at, u.rate_window_requests
    into v_used, v_requests, v_window_started, v_window_requests
  from public.ai_daily_usage u
  where u.user_id = p_user_id and u.usage_date = v_day
  for update;

  if v_window_started <= now() - interval '60 seconds' then
    v_window_started := now();
    v_window_requests := 0;
  end if;

  if v_window_requests >= p_minute_limit then
    return query select false, 'rate_limit'::text, v_used,
      greatest(p_daily_limit - v_used, 0), v_requests;
    return;
  end if;

  if v_used + p_credit_cost > p_daily_limit then
    return query select false, 'daily_limit'::text, v_used,
      greatest(p_daily_limit - v_used, 0), v_requests;
    return;
  end if;

  v_used := v_used + p_credit_cost;
  v_requests := v_requests + 1;
  v_window_requests := v_window_requests + 1;

  update public.ai_daily_usage u
  set credits_used = v_used,
      requests = v_requests,
      rate_window_started_at = v_window_started,
      rate_window_requests = v_window_requests,
      updated_at = now()
  where u.user_id = p_user_id and u.usage_date = v_day;

  return query select true, 'ok'::text, v_used,
    greatest(p_daily_limit - v_used, 0), v_requests;
end;
$$;

revoke all on function public.consume_ai_daily_quota(uuid, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_ai_daily_quota(uuid, integer, integer, integer)
  to service_role;

comment on table public.ai_daily_usage is
  'Server-only daily/fixed-window usage counters for LexPDF Workers AI.';
''',
)

# Backend contract check becomes part of Backend Foundation npm check.
write(
    "backend/cloudflare/scripts/verify-ai-explain.mjs",
    '''import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const worker = readFileSync(resolve(root, 'src/index.ts'), 'utf8');
const wrangler = readFileSync(resolve(root, 'wrangler.toml'), 'utf8');
const migration = readFileSync(
  resolve(root, '../supabase/migrations/20260917210000_add_ai_usage_quota.sql'),
  'utf8',
);

for (const expected of [
  '/v1/ai/explain',
  '@cf/zai-org/glm-4.7-flash',
  '@cf/google/gemma-4-26b-a4b-it',
  'consumeAiQuota',
  'SUPABASE_SECRET_KEY',
  'fallbackUsed',
]) {
  if (!worker.includes(expected)) throw new Error(`Missing AI worker contract: ${expected}`);
}
if (!/\[ai\]\s*\nbinding\s*=\s*"AI"/m.test(wrangler)) {
  throw new Error('Workers AI binding is missing from wrangler.toml');
}
for (const expected of [
  'enable row level security',
  'revoke all on public.ai_daily_usage from public, anon, authenticated',
  'security definer',
  'consume_ai_daily_quota',
  'to service_role',
]) {
  if (!migration.includes(expected)) throw new Error(`Missing AI quota invariant: ${expected}`);
}
console.log('Workers AI explanation contracts verified.');
''',
)

path = "backend/cloudflare/package.json"
text = read(path)
text = replace_once(
    text,
    '"check": "tsc --noEmit && node scripts/verify-upload-limit.mjs"',
    '"check": "tsc --noEmit && node scripts/verify-upload-limit.mjs && node scripts/verify-ai-explain.mjs"',
    "backend package AI check",
)
write(path, text)

# Flutter source contract: selection action, depth, authenticated gateway and no secret in APK.
write(
    "apps/lexpdf_app/test/ai_selected_explanation_contract_test.dart",
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected PDF text exposes authenticated Workers AI explanation flow', () {
    final menu = File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();
    final workspace =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final screen = File('lib/src/screens/ai_selection_explanation_screen.dart')
        .readAsStringSync();
    final remote = File('lib/src/core/ai/remote_ai_engine.dart').readAsStringSync();
    final config = File('lib/src/core/backend/backend_config.dart').readAsStringSync();

    expect(menu, contains("label: 'Explicar com IA'"));
    expect(menu, isNot(contains("label: 'Questão'")));
    expect(workspace, contains('AiSelectionExplanationScreen('));
    expect(screen, contains("label: 'Rápida'"));
    expect(screen, contains("label: 'Detalhada'"));
    expect(screen, contains("label: 'Aprofundada'"));
    expect(screen, contains('currentSession?.accessToken'));
    expect(remote, contains("'depth': explanationDepth.name"));
    expect(config, contains('/v1/ai/explain'));
    expect(config, isNot(contains('SUPABASE_SECRET_KEY')));
  });
}
''',
)

# Update existing remote contract with depth model coverage (source-level + enum behavior).
path = "apps/lexpdf_app/test/remote_ai_engine_contract_test.dart"
text = read(path)
text = replace_once(
    text,
    """import 'package:lexpdf_app/src/core/ai/ai_input_policy.dart';\n""",
    """import 'dart:io';\n\nimport 'package:lexpdf_app/src/core/ai/ai_input_policy.dart';\nimport 'package:lexpdf_app/src/core/ai/ai_models.dart';\n""",
    "remote contract imports",
)
text = replace_once(
    text,
    """void main() {\n""",
    """void main() {\n  test('explanation depth contract has three user-facing levels', () {\n    expect(AiExplanationDepth.values, hasLength(3));\n    expect(AiExplanationDepth.quick.label, 'Rápida');\n    expect(AiExplanationDepth.detailed.label, 'Detalhada');\n    expect(AiExplanationDepth.deep.label, 'Aprofundada');\n    final source = File('lib/src/core/ai/remote_ai_engine.dart').readAsStringSync();\n    expect(source, contains(\"'depth': explanationDepth.name\"));\n  });\n\n""",
    "remote depth test",
)
write(path, text)

# Documentation: record provider, privacy boundary and limits.
write(
    "docs/AI_WORKERS_EXPLANATION.md",
    '''# LexPDF — explicação de seleção com Workers AI\n\n## Fluxo\n\n`seleção PDF -> Explicar com IA -> Cloudflare Worker -> Workers AI`\n\nO APK nunca contém chave privada do provedor. O Worker autentica o usuário pelo token Supabase já usado pelo LexPDF e aplica quota no servidor.\n\n## Níveis\n\n- **Rápida**: 1 crédito, resposta curta, modelo primário GLM-4.7-Flash.\n- **Detalhada**: 2 créditos, modelo primário Gemma 4 26B.\n- **Aprofundada**: 4 créditos, resposta mais longa e estruturada, modelo primário Gemma 4 26B.\n\nSe o modelo primário falhar, o Worker tenta automaticamente o outro modelo.\n\n## Limites padrão\n\n- 240 créditos por usuário/dia (UTC).\n- 12 solicitações por minuto por usuário.\n- 12.000 caracteres por seleção.\n- Rápida: até 350 tokens de saída.\n- Detalhada: até 800 tokens.\n- Aprofundada: até 1.400 tokens.\n\nOs créditos são um mecanismo interno de proteção do LexPDF e não representam diretamente Neurons da Cloudflare.\n\n## Segurança e confiabilidade\n\nO prompt obriga a distinguir o conteúdo apoiado pelo trecho de informação complementar, não inventar jurisprudência/legislação atual e declarar contexto insuficiente. Como todo modelo generativo pode errar, informações críticas devem ser confirmadas em fonte oficial.\n\n## Runtime\n\nO `wrangler.toml` declara o binding `AI`. A quota usa a função Supabase `consume_ai_daily_quota`, acessível apenas ao `service_role`; `SUPABASE_SECRET_KEY` permanece segredo do Worker e nunca é compilado no aplicativo.\n''',
)

print('Cloudflare AI explanation codemod applied successfully.')
