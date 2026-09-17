import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/ocr/mobile_pdf_ocr_service.dart';
import '../core/storage/local_ocr_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_pdf_workspace_session_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'pdf_workspace_stylus_screen.dart' as editor;

/// Persistent multi-document shell for the unified PDF editor.
///
/// Every tab owns its own editor State through an IndexedStack, so switching
/// documents does not destroy the active PDF viewer. OCR/indexing is performed
/// incrementally in the background by this shell so navigation remains usable.
class PdfWorkspaceScreen extends StatefulWidget {
  const PdfWorkspaceScreen({
    required this.document,
    required this.store,
    required this.annotations,
    this.initialPage = 1,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore store;
  final LocalTextAnnotationStore annotations;
  final int initialPage;

  @override
  State<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends State<PdfWorkspaceScreen>
    with WidgetsBindingObserver {
  static const int _maxTabs = 10;

  final DocumentPickerService _picker = const DocumentPickerService();
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'pdf-tab-shell');
  final List<_WorkspaceTab> _tabs = <_WorkspaceTab>[];
  final Map<String, _WorkspaceOcrTask> _ocrTasks = <String, _WorkspaceOcrTask>{};
  final Set<String> _indexPrompted = <String>{};

  late final LocalPdfWorkspaceSessionStore _sessionStore =
      LocalPdfWorkspaceSessionStore(widget.store.db);
  late final LocalPdfInkStore _inkStore = LocalPdfInkStore(widget.store.db);
  late final LocalReadingProgressStore _progressStore =
      LocalReadingProgressStore(widget.store.db);
  late final LocalOcrStore _ocrStore = LocalOcrStore(widget.store.db);
  late final MobilePdfOcrService _ocrService = MobilePdfOcrService(
    ocrStore: _ocrStore,
    navigationStore: widget.store,
  );

  int _activeIndex = 0;
  bool _restoring = true;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs.add(
      _WorkspaceTab(
        document: widget.document,
        initialPage: widget.initialPage < 1 ? 1 : widget.initialPage,
      ),
    );
    unawaited(_restoreSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_saveSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final task in _ocrTasks.values) {
      task.cancelRequested = true;
    }
    unawaited(_saveSession());
    _shortcutFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final saved = await _sessionStore.load();
      final restored = <_WorkspaceTab>[];
      final seen = <String>{};

      for (final savedTab in saved.tabs) {
        final path = savedTab.document.localPath;
        if (path == null || path.isEmpty || !File(path).existsSync()) continue;
        if (!seen.add(savedTab.document.id)) continue;
        final progress = await _progressStore.get(savedTab.document.id);
        restored.add(
          _WorkspaceTab(
            document: savedTab.document,
            initialPage: progress?.pageNumber ?? savedTab.initialPage,
          ),
        );
        if (restored.length >= _maxTabs) break;
      }

      final incomingIndex = restored.indexWhere(
        (tab) => tab.document.id == widget.document.id,
      );
      if (incomingIndex < 0) {
        if (restored.length >= _maxTabs) restored.removeAt(0);
        restored.add(
          _WorkspaceTab(
            document: widget.document,
            initialPage: widget.initialPage < 1 ? 1 : widget.initialPage,
          ),
        );
      }

      final active = restored.indexWhere(
        (tab) => tab.document.id == widget.document.id,
      );
      if (!mounted) return;
      setState(() {
        _tabs
          ..clear()
          ..addAll(restored);
        _activeIndex = active < 0 ? 0 : active;
        _restoring = false;
      });
      await _saveSession();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_inspectActiveDocumentForIndexing());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _restoring = false);
    }
  }

  Future<void> _saveSession() async {
    if (_tabs.isEmpty) {
      await _sessionStore.clear();
      return;
    }
    final safeIndex = _activeIndex.clamp(0, _tabs.length - 1).toInt();
    await _sessionStore.save(
      tabs: [
        for (final tab in _tabs)
          PdfWorkspaceTabState(
            document: tab.document,
            initialPage: tab.initialPage,
          ),
      ],
      activeDocumentId: _tabs[safeIndex].document.id,
    );
  }

  Future<void> _openAnotherPdf() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickPdf();
      if (picked == null || !mounted) return;
      final existing = _tabs.indexWhere((tab) => tab.document.id == picked.id);
      if (existing >= 0) {
        setState(() => _activeIndex = existing);
        await _saveSession();
        unawaited(_inspectActiveDocumentForIndexing());
        return;
      }
      if (_tabs.length >= _maxTabs) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feche uma aba antes de abrir outro PDF (limite: 10).'),
          ),
        );
        return;
      }
      setState(() {
        _tabs.add(_WorkspaceTab(document: picked, initialPage: 1));
        _activeIndex = _tabs.length - 1;
      });
      await _saveSession();
      unawaited(_inspectActiveDocumentForIndexing());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isNotEmpty) {
        if (_activeIndex > index) {
          _activeIndex--;
        } else if (_activeIndex >= _tabs.length) {
          _activeIndex = _tabs.length - 1;
        }
      }
    });
    if (_tabs.isEmpty) {
      await _sessionStore.clear();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await _saveSession();
  }

  Future<void> _activateTab(int index) async {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    setState(() => _activeIndex = index);
    await _saveSession();
    unawaited(_inspectActiveDocumentForIndexing());
  }

  Future<void> _undo() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeIndex];
    final result = await _inkStore.undo(tab.document.id);
    if (!mounted) return;
    if (!result.changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para desfazer neste PDF.')),
      );
      return;
    }
    setState(() {
      tab.initialPage = result.pageNumber;
      tab.generation += 1;
    });
    await _saveSession();
  }

  Future<void> _redo() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeIndex];
    final result = await _inkStore.redo(tab.document.id);
    if (!mounted) return;
    if (!result.changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para refazer neste PDF.')),
      );
      return;
    }
    setState(() {
      tab.initialPage = result.pageNumber;
      tab.generation += 1;
    });
    await _saveSession();
  }

  Future<void> _inspectActiveDocumentForIndexing() async {
    if (!mounted || _tabs.isEmpty) return;
    final document = _tabs[_activeIndex].document;
    if (!_indexPrompted.add(document.id)) return;
    if (_ocrTasks[document.id]?.running == true) return;
    final path = document.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) return;

    final indexed = widget.store.db.database.select('''
      SELECT COUNT(*) AS count
      FROM pdf_page_text_index
      WHERE document_id = ? AND trim(content) <> '';
    ''', [document.id]).single['count'] as int? ?? 0;
    if (indexed > 0) return;

    try {
      final availability = await _ocrService.inspectTextAvailability(filePath: path);
      if (!mounted || _tabs.isEmpty || _tabs[_activeIndex].document.id != document.id) {
        return;
      }
      final message = availability.likelyScanned
          ? 'Este PDF parece digitalizado. OCR/indexação pode rodar em segundo plano.'
          : 'Indexe o texto deste PDF em segundo plano para busca local e Ctrl+F.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(message),
          action: SnackBarAction(
            label: 'Indexar',
            onPressed: () => unawaited(_startBackgroundIndexing(document)),
          ),
        ),
      );
    } catch (_) {
      // Inspection is advisory; opening/reading the PDF must never depend on it.
    }
  }

  Future<void> _startBackgroundIndexing(DocumentRef document) async {
    final path = document.localPath;
    if (path == null || path.isEmpty) return;
    final existing = _ocrTasks[document.id];
    if (existing?.running == true) return;
    final task = existing ?? _WorkspaceOcrTask();
    task
      ..running = true
      ..cancelRequested = false
      ..error = null
      ..summary = null
      ..progress = null;
    _ocrTasks[document.id] = task;
    if (mounted) setState(() {});
    try {
      final summary = await _ocrService.process(
        documentId: document.id,
        filePath: path,
        resume: true,
        isCancelled: () => task.cancelRequested,
        onProgress: (progress) {
          task.progress = progress;
          if (mounted) setState(() {});
        },
      );
      task.summary = summary;
    } catch (error) {
      task.error = error;
    } finally {
      task.running = false;
      if (mounted) setState(() {});
    }
  }

  void _cancelActiveIndexing() {
    if (_tabs.isEmpty) return;
    final task = _ocrTasks[_tabs[_activeIndex].document.id];
    if (task == null || !task.running) return;
    setState(() => task.cancelRequested = true);
  }

  Future<void> _showDocumentSearch() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeIndex];
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pesquisar no PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Digite uma palavra ou expressão',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Pesquisar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || query == null || query.isEmpty) return;

    final rows = widget.store.db.database.select('''
      SELECT page_number, content
      FROM pdf_page_text_index
      WHERE document_id = ? AND lower(content) LIKE ?
      ORDER BY page_number
      LIMIT 200;
    ''', [tab.document.id, '%${query.toLowerCase()}%']);

    if (!mounted) return;
    if (rows.isEmpty) {
      final hasIndex = widget.store.db.database.select('''
        SELECT 1 FROM pdf_page_text_index WHERE document_id = ? LIMIT 1;
      ''', [tab.document.id]).isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasIndex
                ? 'Nenhuma ocorrência de “$query” foi localizada.'
                : 'Este PDF ainda não foi indexado. Inicie OCR/indexação para usar Ctrl+F em PDFs digitalizados.',
          ),
          action: hasIndex
              ? null
              : SnackBarAction(
                  label: 'Indexar',
                  onPressed: () => unawaited(_startBackgroundIndexing(tab.document)),
                ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.70,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final page = row['page_number'] as int;
              final content = row['content'] as String? ?? '';
              return ListTile(
                leading: CircleAvatar(child: Text('$page')),
                title: Text('Página $page'),
                subtitle: Text(
                  _searchSnippet(content, query),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openIndexedSearchPage(page);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _searchSnippet(String content, String query) {
    final lower = content.toLowerCase();
    final index = lower.indexOf(query.toLowerCase());
    if (index < 0) return content.length <= 180 ? content : '${content.substring(0, 180)}…';
    final start = (index - 70).clamp(0, content.length);
    final end = (index + query.length + 100).clamp(0, content.length);
    return '${start > 0 ? '…' : ''}${content.substring(start, end)}${end < content.length ? '…' : ''}';
  }

  void _openIndexedSearchPage(int page) {
    if (_tabs.isEmpty || page < 1) return;
    final tab = _tabs[_activeIndex];
    setState(() {
      tab.initialPage = page;
      tab.generation += 1;
    });
    unawaited(_saveSession());
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_tabs.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final activeTask = _ocrTasks[_tabs[_activeIndex].document.id];
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            unawaited(_undo()),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            unawaited(_redo()),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () => unawaited(_redo()),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
            unawaited(_openAnotherPdf()),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            unawaited(_showDocumentSearch()),
      },
      child: Focus(
        focusNode: _shortcutFocus,
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              _buildTabStrip(),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _activeIndex,
                        children: [
                          for (final tab in _tabs)
                            editor.PdfWorkspaceScreen(
                              key: ValueKey(
                                'pdf-tab-${tab.document.id}-${tab.generation}',
                              ),
                              document: tab.document,
                              store: widget.store,
                              annotations: widget.annotations,
                              initialPage: tab.initialPage,
                            ),
                        ],
                      ),
                    ),
                    if (activeTask != null &&
                        (activeTask.running || activeTask.summary != null || activeTask.error != null))
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _OcrProgressCard(
                          task: activeTask,
                          onCancel: activeTask.running ? _cancelActiveIndexing : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabStrip() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                itemCount: _tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final tab = _tabs[index];
                  final selected = index == _activeIndex;
                  return Material(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => unawaited(_activateTab(index)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 120,
                          maxWidth: 240,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.picture_as_pdf_outlined, size: 17),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  tab.document.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fechar aba',
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                onPressed: () => unawaited(_closeTab(index)),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Pesquisar no PDF (Ctrl+F)',
              onPressed: _showDocumentSearch,
              icon: const Icon(Icons.search, size: 20),
            ),
            IconButton(
              tooltip: 'Desfazer (Ctrl+Z)',
              onPressed: _undo,
              icon: const Icon(Icons.undo, size: 20),
            ),
            IconButton(
              tooltip: 'Refazer (Ctrl+Y)',
              onPressed: _redo,
              icon: const Icon(Icons.redo, size: 20),
            ),
            IconButton(
              tooltip: 'Nova aba de PDF (Ctrl+T)',
              onPressed: _picking ? null : _openAnotherPdf,
              icon: _picking
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 22),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab {
  _WorkspaceTab({
    required this.document,
    required this.initialPage,
  });

  final DocumentRef document;
  int initialPage;
  int generation = 0;
}

class _WorkspaceOcrTask {
  bool running = false;
  bool cancelRequested = false;
  PdfOcrProgress? progress;
  PdfOcrSummary? summary;
  Object? error;
}

class _OcrProgressCard extends StatelessWidget {
  const _OcrProgressCard({required this.task, this.onCancel});

  final _WorkspaceOcrTask task;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = task.progress;
    final summary = task.summary;
    final total = progress?.totalInRange ?? 0;
    final completed = progress?.completedInRange ?? 0;
    return Card(
      elevation: 5,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    task.running
                        ? Icons.document_scanner_outlined
                        : task.error == null
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.running
                          ? 'OCR/indexação em segundo plano'
                          : task.error != null
                              ? 'Indexação interrompida por erro'
                              : summary?.cancelled == true
                                  ? 'Indexação pausada'
                                  : 'Indexação concluída',
                    ),
                  ),
                  if (onCancel != null)
                    IconButton(
                      tooltip: 'Cancelar e preservar progresso',
                      onPressed: onCancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                ],
              ),
              if (task.running) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total > 0 ? completed / total : null,
                ),
                const SizedBox(height: 6),
                Text(
                  progress == null
                      ? 'Preparando páginas…'
                      : 'Página ${progress.pageNumber}/${progress.pageCount} • $completed/$total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (summary != null) ...[
                const SizedBox(height: 4),
                Text(
                  summary.cancelled
                      ? 'O que já foi processado foi salvo. Execute novamente para retomar.'
                      : '${summary.recognizedPages} página(s) processada(s); busca local atualizada incrementalmente.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (task.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${task.error}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
