import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_pdf_workspace_session_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'pdf_workspace_stylus_screen.dart' as editor;

/// Persistent multi-document shell for the unified PDF editor.
///
/// Every tab owns its own editor State through an IndexedStack, so switching
/// documents does not destroy the active PDF viewer. Open tabs and the active
/// document are checkpointed to SQLCipher and reconstructed after an app or
/// workspace restart. Persistent ink Undo/Redo is provided by LocalPdfInkStore.
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

  late final LocalPdfWorkspaceSessionStore _sessionStore =
      LocalPdfWorkspaceSessionStore(widget.store.db);
  late final LocalPdfInkStore _inkStore = LocalPdfInkStore(widget.store.db);
  late final LocalReadingProgressStore _progressStore =
      LocalReadingProgressStore(widget.store.db);

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

      // Explicitly opening a PDF always activates that document. The remaining
      // tabs are recovered around it rather than unexpectedly stealing focus.
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
    final safeIndex = _activeIndex.clamp(0, _tabs.length - 1);
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
      tab
        ..initialPage = result.pageNumber
        ..generation++;
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
      tab
        ..initialPage = result.pageNumber
        ..generation++;
    });
    await _saveSession();
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
    this.generation = 0,
  });

  final DocumentRef document;
  int initialPage;
  int generation;
}
