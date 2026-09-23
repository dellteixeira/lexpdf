import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/documents/document_provider.dart';
import '../core/ink/ink_models.dart';
import '../core/ink/pdf_ink_eraser.dart';
import '../core/ink/pdf_ink_models.dart';
import '../core/pdf/huge_pdf_policy.dart';
import '../core/storage/local_pdf_form_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_study_notebook_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import '../widgets/pdf_android_finger_navigation_region.dart';
import '../widgets/pdf_selection_action_menu.dart';
import '../widgets/pdf_sticky_note_overlay.dart';
import '../widgets/pdf_stylus_page_overlay.dart';
import '../widgets/windows10_pdf_tile_overlay.dart';
import 'ai_selection_explanation_screen.dart';
import 'pdf_export_screen.dart';
import 'pdf_forms_screen.dart';
import 'pdf_ocr_screen.dart';
import 'pdf_page_tools_screen.dart';
import 'pdf_print_screen.dart';

enum _PdfViewMode { continuous, horizontal, facing }

enum _WorkspaceMoreAction {
  readingMode,
  outline,
  bookmarks,
  forms,
  export,
  print,
}

enum _StylusMode { hand, selectText, note, pen, highlighter, eraser }

class PdfWorkspaceScreen extends StatefulWidget {
  const PdfWorkspaceScreen({
    required this.document,
    required this.store,
    required this.annotations,
    this.initialPage = 1,
    this.fullScreen = false,
    this.showDocumentHeader = true,
    this.onToggleFullScreen,
    this.onPageChanged,
    this.onReaderActivity,
    this.onViewerDocumentChanged,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore store;
  final LocalTextAnnotationStore annotations;
  final int initialPage;
  final bool fullScreen;
  final bool showDocumentHeader;
  final VoidCallback? onToggleFullScreen;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onReaderActivity;
  final ValueChanged<PdfDocument?>? onViewerDocumentChanged;

  @override
  State<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends State<PdfWorkspaceScreen> {
  static const _zoomPresets = <int>[25, 50, 75, 100, 125, 150, 200, 300, 400];
  static const _palette = <int>[
    0xFF246BFD,
    0xFF1C1B1F,
    0xFFEF5350,
    0xFF26C6DA,
    0xFF81C784,
    0xFFFFD54F,
    0xFFFFB74D,
    0xFFBA68C8,
  ];

  final PdfViewerController _controller = PdfViewerController();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'pdf-workspace');
  final List<int> _backHistory = <int>[];
  final List<int> _forwardHistory = <int>[];
  final Map<int, List<PdfInkStroke>> _inkByPage = <int, List<PdfInkStroke>>{};

  late final LocalPdfInkStore _inkStore = LocalPdfInkStore(widget.store.db);
  late final PdfSelectionActionMenu _selectionMenu = PdfSelectionActionMenu(
    documentId: widget.document.id,
    store: widget.annotations,
    controller: _controller,
    colorValue: () => _inkColor,
    onChanged: () {
      if (!mounted) return;
      setState(() => _annotationRevision++);
      _controller.invalidate();
    },
    onStudyAction: (
      context,
      selectedText,
      action,
      pageNumber,
      anchorX,
      anchorY,
    ) async {
      if (action.name != 'explain') return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AiSelectionExplanationScreen(
            selectedText: selectedText,
            studyStore: LocalStudyNotebookStore(widget.store.db),
            annotations: widget.annotations,
            sourceDocumentId: widget.document.id,
            sourceDocumentTitle: widget.document.name,
            sourcePage: pageNumber,
            anchorX: anchorX,
            anchorY: anchorY,
            onAnnotationSaved: () {
              if (!mounted) return;
              setState(() => _annotationRevision++);
              _controller.invalidate();
            },
          ),
        ),
      );
    },
  );
  late _StylusMode _stylusMode;
  List<PdfBookmark> _bookmarks = const <PdfBookmark>[];
  List<PdfOutlineNode> _outline = const <PdfOutlineNode>[];
  PdfDocument? _document;
  int _page = 1;
  int _zoomPercent = 100;
  int _inkLoadGeneration = 0;
  int _inkCount = 0;
  int _annotationRevision = 0;
  int _internalLinkNavigationGeneration = 0;
  bool _hasTextSelection = false;
  int _inkColor = 0xFF246BFD;
  double _inkWidth = 3.0;
  double _eraserWidth = 36.0;
  bool _historyNavigation = false;
  bool _loadingInk = false;
  bool _readingMode = false;
  bool _fullScreenForcedReadingMode = false;
  int? _chromeTransitionPage;
  _PdfViewMode _viewMode = _PdfViewMode.continuous;
  Offset? _zoomAnchorLocal;

  bool get _mobile => defaultTargetPlatform == TargetPlatform.android;


  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  bool get _windows10Tiles => isWindows10ManualTileRenderingEnabled();

  int _renderCacheBudget(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: _windows,
      pageCount: _document?.pages.length ?? 0,
      viewportWidth: size.width,
      viewportHeight: size.height,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  bool get _inkMode => switch (_stylusMode) {
    _StylusMode.pen || _StylusMode.highlighter || _StylusMode.eraser => true,
    _ => false,
  };

  bool get _eraserMode => _stylusMode == _StylusMode.eraser;

  bool get _textSelectionMode => _stylusMode == _StylusMode.selectText;

  /// Acrobat/Xodo-style mobile selection:
  /// - Hand mode remains a navigation tool for normal drags;
  /// - long-press with finger or stylus can still select a word on Android;
  /// - explicit Select mode keeps free text-selection behavior;
  /// - ink/note tools retain exclusive pointer ownership.
  bool get _textSelectionEnabled =>
      _textSelectionMode || (_android && _stylusMode == _StylusMode.hand);

  bool get _textSelectionOwnsGesture =>
      _textSelectionMode || _hasTextSelection;

  InkTool get _inkTool => switch (_stylusMode) {
    _StylusMode.highlighter => InkTool.highlighter,
    _ => InkTool.pen,
  };

  double get _effectiveInkWidth => switch (_inkTool) {
    InkTool.pen => _inkWidth,
    InkTool.pencil => _inkWidth * 0.8,
    InkTool.highlighter => _inkWidth * 5.0,
  };

  @override
  void initState() {
    super.initState();
    _page = math.max(1, widget.initialPage);
    // Open every PDF in navigation mode. Drawing tools are opt-in so
    // touch/drag gestures immediately move through pages on mobile and desktop.
    _stylusMode = _StylusMode.hand;
    _controller.addListener(_syncZoomFromController);
    unawaited(_reloadBookmarks());
    unawaited(_loadInkCount());
  }

  @override
  void didUpdateWidget(covariant PdfWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullScreen == widget.fullScreen) return;

    // Changing the amount of chrome changes the viewer viewport. pdfrx may
    // transiently report page 1 while it recomputes that viewport, so capture
    // the actual reading position before rebuilding and restore it after the
    // new layout settles.
    final preservedPage = _controller.pageNumber ?? _page;
    _chromeTransitionPage = preservedPage;
    if (widget.fullScreen) {
      if (!_readingMode) {
        _readingMode = true;
        _fullScreenForcedReadingMode = true;
      }
    } else if (_fullScreenForcedReadingMode) {
      _readingMode = false;
      _fullScreenForcedReadingMode = false;
    }
    _controller.invalidate();
    _schedulePageRestoreAfterChromeChange(preservedPage);
  }

  void _schedulePageRestoreAfterChromeChange(int pageNumber) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restorePageAfterChromeChange(pageNumber));
    });
  }

  Future<void> _restorePageAfterChromeChange(int pageNumber) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_controller.isReady) return;

    Future<void> restoreIfNeeded() async {
      if (!mounted || !_controller.isReady) return;
      if (_controller.pageNumber == pageNumber) return;
      await _controller.goToPage(
        pageNumber: pageNumber,
        anchor: PdfPageAnchor.top,
        duration: Duration.zero,
      );
    }

    await restoreIfNeeded();
    await WidgetsBinding.instance.endOfFrame;
    await restoreIfNeeded();

    if (!mounted) return;
    if (_chromeTransitionPage == pageNumber) {
      _chromeTransitionPage = null;
    }
    if (_page != pageNumber) {
      setState(() => _page = pageNumber);
    }
    widget.onPageChanged?.call(pageNumber);
  }

  @override
  void dispose() {
    _inkLoadGeneration++;
    widget.onViewerDocumentChanged?.call(null);
    _controller.removeListener(_syncZoomFromController);
    _keyboardFocusNode.dispose();
    if (_android && _readingMode) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF')),
        body: const Center(
          child: Text('O PDF precisa estar disponível offline.'),
        ),
      );
    }

    return Scaffold(
      appBar: (_readingMode || !widget.showDocumentHeader)
          ? null
          : AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PDF'),
            Text(
              widget.document.name,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: Text('Pág. $_page')),
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              unawaited(_previousPage()),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              unawaited(_nextPage()),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              unawaited(_scrollBy(110)),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              unawaited(_scrollBy(-110)),
          const SingleActivator(LogicalKeyboardKey.pageUp): () =>
              unawaited(_previousPage()),
          const SingleActivator(LogicalKeyboardKey.pageDown): () =>
              unawaited(_nextPage()),
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              _requestFullScreen,
          const SingleActivator(LogicalKeyboardKey.f11): _requestFullScreen,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (widget.fullScreen) {
              widget.onToggleFullScreen?.call();
            } else if (_readingMode) {
              unawaited(_setReadingMode(false));
            }
          },
        },
        child: Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          child: Column(
            children: [
              if (!_readingMode) _buildCommandBar(path),
              if (!_readingMode) const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: PdfAndroidFingerNavigationRegion(
                        // In text-selection mode, one-finger drag belongs
                        // exclusively to pdfrx's native text-selection engine.
                        // If our Android pan router also moves the controller,
                        // the page slides underneath the selection handle.
                        active: _android && !_textSelectionOwnsGesture,
                        controller: _controller,
                        onFocalPointChanged: (position) {
                          widget.onReaderActivity?.call();
                          _zoomAnchorLocal = position;
                        },
                        onNavigationEnd: () {
                          widget.onReaderActivity?.call();
                          _syncZoomFromController();
                        },
                        child: PdfViewer.file(
                          path,
                          controller: _controller,
                          initialPageNumber: _page,
                          useProgressiveLoading: true,
                          params: PdfViewerParams(
                            limitRenderingCache: true,
                            maxImageBytesCachedOnMemory:
                                _renderCacheBudget(context),
                            horizontalCacheExtent: _windows
                                ? 1.0
                                : HugePdfPolicy.androidCacheExtent,
                            verticalCacheExtent: _windows
                                ? 1.0
                                : HugePdfPolicy.androidCacheExtent,
                            onePassRenderingSizeThreshold: _windows10Tiles
                                ? 1000
                                : (_windows
                                      ? 6000
                                      : HugePdfPolicy
                                          .androidOnePassRenderingSizeThreshold),
                            getPageRenderingScale:
                                (context, page, controller, estimatedScale) {
                                  // The Win10 manual tile layer supplies the visible
                                  // page pixels. Keep pdfrx's hidden backing page at
                                  // 72 dpi so it never allocates the giant bitmap
                                  // path that corrupts on affected Windows 10 PCs.
                                  if (_windows10Tiles) return 1.0;

                                  final maxRenderPixels = _windows
                                      ? 6000.0
                                      : HugePdfPolicy.androidMaxRenderLongEdge;
                                  final width = page.width * estimatedScale;
                                  final height = page.height * estimatedScale;
                                  if (width <= maxRenderPixels &&
                                      height <= maxRenderPixels) {
                                    return estimatedScale;
                                  }
                                  return math.min(
                                    maxRenderPixels / page.width,
                                    maxRenderPixels / page.height,
                                  );
                                },
                            behaviorControlParams:
                                PdfViewerBehaviorControlParams(
                                  // Keep page geometry lazy on Android so opening 1,000–5,000+
                                  // page documents does not eagerly measure the whole file. Windows
                                  // retains eager dimensions because its desktop/manual-tile path
                                  // has separate rendering constraints. Internal PDF destinations
                                  // are resolved by the guarded navigation routine below.
                                  loadPageDimensionsOnDemand: !_windows,
                                  enableLowResolutionPagePreview:
                                      !_windows && !_android,
                                  trailingPageLoadingDelay: _windows
                                      ? const Duration(milliseconds: 100)
                                      : HugePdfPolicy
                                          .androidTrailingPageLoadingDelay,
                                  pageImageCachingDelay: _windows
                                      ? const Duration(milliseconds: 20)
                                      : HugePdfPolicy
                                          .androidPageImageCachingDelay,
                                  partialImageLoadingDelay: _windows
                                      ? Duration.zero
                                      : HugePdfPolicy
                                          .androidPartialImageLoadingDelay,
                                ),
                            // Android touch is routed explicitly by
                            // PdfAndroidFingerNavigationRegion. Disabling the
                            // internal recognizer prevents duplicate pan/zoom and
                            // makes S Pen + finger behavior deterministic on
                            // Samsung tablets and Xiaomi phones.
                            panAxis: PanAxis.free,
                            boundaryMargin: EdgeInsets.all(
                              _mobile ? 320.0 : 120.0,
                            ),
                            // Selection is a modal tool: dragging selects text,
                            // it never pans/scales the document. Navigation
                            // returns immediately when the Hand tool is chosen.
                            panEnabled:
                                !_android &&
                                !_textSelectionMode &&
                                (_mobile ||
                                    (_stylusMode != _StylusMode.note &&
                                        !_inkMode)),
                            scaleEnabled:
                                !_android &&
                                !_textSelectionMode &&
                                (_mobile ||
                                    (_stylusMode != _StylusMode.note &&
                                        !_inkMode)),
                            onInteractionStart: (details) {
                              widget.onReaderActivity?.call();
                              _zoomAnchorLocal = details.localFocalPoint;
                            },
                            onInteractionUpdate: (details) {
                              widget.onReaderActivity?.call();
                              _zoomAnchorLocal = details.localFocalPoint;
                            },
                            onInteractionEnd: (_) {
                              widget.onReaderActivity?.call();
                              _syncZoomFromController();
                            },
                            buildContextMenu: _textSelectionEnabled
                                ? _selectionMenu.buildContextMenu
                                : null,
                            textSelectionParams: PdfTextSelectionParams(
                              enabled: _textSelectionEnabled,
                              // In Hand mode on Android, long-press selects one
                              // word and always exposes handles, including for
                              // S Pen. Explicit Select mode stays adaptive so
                              // drag-to-select remains available.
                              enableSelectionHandles:
                                  _android && !_textSelectionMode ? true : null,
                              showContextMenuAutomatically: true,
                              onSelectionHandlePanStart: (_) {
                                // Kill any kinetic pan left over from Hand mode
                                // before the first handle movement.
                                _controller.stopInteractiveViewerAnimation();
                              },
                              onTextSelectionChange: (selection) {
                                final hasSelection =
                                    selection.hasSelectedText;
                                if (mounted &&
                                    _hasTextSelection != hasSelection) {
                                  if (hasSelection && _android) {
                                    unawaited(
                                      HapticFeedback.selectionClick(),
                                    );
                                  }
                                  setState(
                                    () => _hasTextSelection = hasSelection,
                                  );
                                }
                                if (_controller.isReady) {
                                  _controller.invalidate();
                                }
                              },
                            ),
                            pagePaintCallbacks: _windows10Tiles
                                ? const []
                                : [_selectionMenu.paint],
                            layoutPages: switch (_viewMode) {
                              _PdfViewMode.continuous => null,
                              _PdfViewMode.horizontal => _horizontalLayout,
                              _PdfViewMode.facing => _facingLayout,
                            },
                            linkHandlerParams: PdfLinkHandlerParams(
                              onLinkTap: (link) {
                                final url = link.url;
                                if (url != null) {
                                  unawaited(_openExternalLink(url));
                                  return;
                                }
                                final dest = link.dest;
                                if (dest != null) {
                                  unawaited(_goToInternalPdfDestination(dest));
                                }
                              },
                            ),
                            pageOverlaysBuilder: (context, pageRect, page) => [
                              if (_windows10Tiles)
                                Positioned.fill(
                                  child: Windows10PdfTileOverlay(
                                    key: ValueKey(
                                      'win10-tiles-${page.pageNumber}',
                                    ),
                                    page: page,
                                    pageRect: pageRect,
                                    controller: _controller,
                                  ),
                                ),
                              if (_windows10Tiles)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _SelectionMarkupOverlayPainter(
                                        menu: _selectionMenu,
                                        pageRect: pageRect,
                                        page: page,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned.fill(
                                child: PdfStylusPageOverlay(
                                  key: ValueKey(
                                    'stylus-${page.pageNumber}-${_stylusMode.name}-$_inkCount-${_eraserWidth.toStringAsFixed(1)}',
                                  ),
                                  documentId: widget.document.id,
                                  pageNumber: page.pageNumber,
                                  strokes:
                                      _inkByPage[page.pageNumber] ?? const [],
                                  enabled: _inkMode,
                                  tool: _inkTool,
                                  colorValue: _inkColor,
                                  strokeWidth: _effectiveInkWidth,
                                  eraserMode: _eraserMode,
                                  eraserRadius: _eraserWidth / 2,
                                  onStrokeCompleted: _onStrokeCompleted,
                                  onEraseApplied: _onEraseApplied,
                                ),
                              ),
                              Positioned.fill(
                                child: PdfStickyNoteOverlay(
                                  key: ValueKey(
                                    'sticky-${page.pageNumber}-${_stylusMode.name}-$_annotationRevision',
                                  ),
                                  documentId: widget.document.id,
                                  pageNumber: page.pageNumber,
                                  store: widget.annotations.objectStore,
                                  createEnabled:
                                      _stylusMode == _StylusMode.note,
                                  onNoteSaved: () {
                                    if (!mounted) return;
                                    setState(
                                      () => _stylusMode = _StylusMode.hand,
                                    );
                                    _controller.invalidate();
                                  },
                                ),
                              ),
                            ],
                            onViewerReady: (document, controller) {
                              _document = document;
                              widget.onViewerDocumentChanged?.call(document);
                              _syncZoomFromController();
                              if (mounted) setState(() {});

                              // Reader-first startup: make the first page usable
                              // before optional outline/annotation hydration.
                              // On Android this avoids stacking text/object work
                              // on top of PDFium's initial page render.
                              final secondaryDelay = _android
                                  ? HugePdfPolicy.androidSecondaryWorkDelay
                                  : Duration.zero;
                              Future<void>.delayed(secondaryDelay, () async {
                                if (!mounted || !identical(_document, document)) {
                                  return;
                                }
                                await _loadOutline(document);
                                if (!mounted || !identical(_document, document)) {
                                  return;
                                }
                                await _loadInkWindow(document, _page);
                                if (!mounted || !identical(_document, document)) {
                                  return;
                                }
                                await _selectionMenu.load(document);
                              });
                            },
                            onPageChanged: _onPageChanged,
                          ),
                        ),
                      ),
                    ),
                    if (!_readingMode && _loadingInk)
                      const Positioned(
                        right: 16,
                        bottom: 16,
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('Carregando escrita'),
                              ],
                            ),
                          ),
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

  Future<void> _goToInternalPdfDestination(PdfDest dest) async {
    final document = _document;
    final targetPage = dest.pageNumber;
    if (document == null ||
        targetPage < 1 ||
        targetPage > document.pages.length ||
        !_controller.isReady) {
      return;
    }

    if (!_android) {
      await _controller.goToDest(dest);
      return;
    }

    // A newer tap supersedes an older in-flight link resolution. This matters
    // on large Android documents where lazy geometry may take a few frames to
    // become available.
    final generation = ++_internalLinkNavigationGeneration;

    // Stage 1: navigate by physical page number. With lazy page dimensions this
    // explicitly asks pdfrx to materialize the target page geometry before we
    // apply /XYZ, /Fit, or other intra-page destination coordinates.
    await _controller.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: Duration.zero,
    );
    final pageReady = await _waitForInternalLinkPage(
      targetPage: targetPage,
      generation: generation,
    );
    if (!pageReady) return;

    // Stage 2: once the physical target page is active, apply the exact PDF
    // destination so intra-page links keep their intended position/zoom.
    final moved = await _controller.goToDest(dest, duration: Duration.zero);
    if (!_isCurrentInternalLinkNavigation(generation)) return;
    if (!moved) {
      await _restoreInternalLinkTargetPage(targetPage, generation);
      return;
    }

    // Stage 3: verify after layout settles. Some Android/PDFium combinations
    // accept a destination transform before the lazy target geometry is fully
    // published. If it resolves to a different physical page, fall back to the
    // correct page without ever applying +1/-1 page-number guesses.
    await _waitForInternalLinkLayout(generation);
    if (!_isCurrentInternalLinkNavigation(generation)) return;
    final currentPage = _controller.pageNumber;
    if (currentPage != null && currentPage != targetPage) {
      await _restoreInternalLinkTargetPage(targetPage, generation);
    }
  }

  bool _isCurrentInternalLinkNavigation(int generation) =>
      mounted &&
      _controller.isReady &&
      generation == _internalLinkNavigationGeneration;

  Future<bool> _waitForInternalLinkPage({
    required int targetPage,
    required int generation,
  }) async {
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!_isCurrentInternalLinkNavigation(generation)) return false;
      if (_controller.pageNumber == targetPage) return true;
      await _waitForInternalLinkLayout(generation);
    }

    // One bounded retry handles devices that need an additional layout pass
    // after the first lazy page-dimension request.
    if (!_isCurrentInternalLinkNavigation(generation)) return false;
    await _controller.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: Duration.zero,
    );
    await _waitForInternalLinkLayout(generation);
    return _isCurrentInternalLinkNavigation(generation) &&
        _controller.pageNumber == targetPage;
  }

  Future<void> _waitForInternalLinkLayout(int generation) async {
    if (!_isCurrentInternalLinkNavigation(generation)) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  Future<void> _restoreInternalLinkTargetPage(
    int targetPage,
    int generation,
  ) async {
    if (!_isCurrentInternalLinkNavigation(generation)) return;
    await _controller.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: Duration.zero,
    );
  }

  Widget _buildCommandBar(String path) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final rowHeight = compact ? 44.0 : 50.0;
          return SizedBox(
            height: rowHeight * 2 + 5,
            child: Column(
              children: [
                SizedBox(
                  height: rowHeight,
                  child: _fitToolbarRow(
                    constraints.maxWidth,
                    <Widget>[
                      IconButton(
                        tooltip: 'Voltar na navegação',
                        onPressed: _backHistory.isEmpty ? null : _goBack,
                        icon: const Icon(Icons.arrow_back_outlined),
                      ),
                      IconButton(
                        tooltip: 'Avançar na navegação',
                        onPressed: _forwardHistory.isEmpty ? null : _goForward,
                        icon: const Icon(Icons.arrow_forward_outlined),
                      ),
                      IconButton(
                        tooltip: 'Página anterior',
                        onPressed: _page <= 1 ? null : _previousPage,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Próxima página',
                        onPressed:
                            _document != null && _page >= _document!.pages.length
                                ? null
                                : _nextPage,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      IconButton(
                        tooltip: 'Ir para página',
                        onPressed: _jumpToPage,
                        icon: const Icon(Icons.numbers_outlined),
                      ),
                      const SizedBox(width: 4),
                      _stylusButton(
                        _StylusMode.hand,
                        Icons.pan_tool_outlined,
                        'Mão',
                        compact: compact,
                      ),
                      _stylusButton(
                        _StylusMode.selectText,
                        Icons.text_fields_outlined,
                        'Selecionar',
                        compact: compact,
                      ),
                      _stylusButton(
                        _StylusMode.note,
                        Icons.sticky_note_2_outlined,
                        'Anotar',
                        compact: compact,
                      ),
                      _stylusButton(
                        _StylusMode.pen,
                        Icons.edit,
                        'Caneta',
                        compact: compact,
                      ),
                      IconButton(
                        tooltip: widget.fullScreen
                            ? 'Sair do modo leitura (Ctrl+H)'
                            : 'Modo leitura (Ctrl+H)',
                        onPressed: _requestFullScreen,
                        icon: Icon(
                          widget.fullScreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 5, color: scheme.outlineVariant),
                SizedBox(
                  height: rowHeight,
                  child: _fitToolbarRow(
                    constraints.maxWidth,
                    <Widget>[
                      _stylusButton(
                        _StylusMode.highlighter,
                        Icons.border_color_outlined,
                        'Marca-texto',
                        compact: compact,
                      ),
                      _stylusButton(
                        _StylusMode.eraser,
                        Icons.auto_fix_normal_outlined,
                        'Borracha',
                        compact: compact,
                      ),
                      IconButton(
                        tooltip: _eraserMode
                            ? 'Espessura da borracha: ${_eraserWidth.toStringAsFixed(0)}'
                            : 'Cor e espessura da caneta',
                        onPressed: _showInkSettings,
                        icon: _eraserMode
                            ? const Icon(Icons.line_weight)
                            : Icon(
                                Icons.palette_outlined,
                                color: Color(_inkColor),
                              ),
                      ),
                      IconButton(
                        tooltip: 'Desfazer último traço nesta página',
                        onPressed: (_inkByPage[_page]?.isNotEmpty ?? false)
                            ? _undoInk
                            : null,
                        icon: const Icon(Icons.undo),
                      ),
                      _toolbarCommandButton(
                        compact: compact,
                        icon: Icons.grid_view_outlined,
                        label: 'Miniaturas',
                        onPressed: _document == null
                            ? null
                            : () => _showThumbnails(path),
                      ),
                      if (!compact)
                        _toolbarCommandButton(
                          compact: false,
                          icon: Icons.account_tree_outlined,
                          label: 'Sumário',
                          onPressed: _outline.isEmpty ? null : _showOutline,
                        ),
                      if (!compact)
                        _toolbarCommandButton(
                          compact: false,
                          icon: Icons.bookmarks_outlined,
                          label: 'Marcadores',
                          onPressed: _showBookmarks,
                        ),
                      IconButton(
                        tooltip: 'Marcar página $_page',
                        onPressed: _toggleCurrentBookmark,
                        icon: Icon(
                          _bookmarks.any((item) => item.pageNumber == _page)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                      ),
                      _toolbarCommandButton(
                        compact: compact,
                        icon: Icons.edit_document,
                        label: 'Páginas',
                        onPressed: _openPageTools,
                      ),
                      _toolbarCommandButton(
                        compact: compact,
                        icon: Icons.document_scanner_outlined,
                        label: 'OCR',
                        onPressed: _openOcr,
                      ),
                      IconButton(
                        tooltip: 'Zoom -',
                        onPressed: _zoomOut,
                        icon: const Icon(Icons.zoom_out),
                      ),
                      _buildZoomMenu(),
                      IconButton(
                        tooltip: 'Zoom +',
                        onPressed: _zoomIn,
                        icon: const Icon(Icons.zoom_in),
                      ),
                      PopupMenuButton<_PdfViewMode>(
                        tooltip: 'Modo de visualização',
                        initialValue: _viewMode,
                        onSelected: (value) {
                          setState(() => _viewMode = value);
                          _controller.invalidate();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _PdfViewMode.continuous,
                            child: Text('Contínuo vertical'),
                          ),
                          PopupMenuItem(
                            value: _PdfViewMode.horizontal,
                            child: Text('Horizontal'),
                          ),
                          PopupMenuItem(
                            value: _PdfViewMode.facing,
                            child: Text('Páginas duplas'),
                          ),
                        ],
                        icon: const Icon(Icons.view_carousel_outlined),
                      ),
                      PopupMenuButton<_WorkspaceMoreAction>(
                        tooltip: 'Mais ferramentas',
                        onSelected: _handleMoreAction,
                        itemBuilder: (context) => [
                          if (compact)
                            PopupMenuItem(
                              value: _WorkspaceMoreAction.outline,
                              enabled: _outline.isNotEmpty,
                              child: const ListTile(
                                leading: Icon(Icons.account_tree_outlined),
                                title: Text('Sumário'),
                              ),
                            ),
                          if (compact)
                            const PopupMenuItem(
                              value: _WorkspaceMoreAction.bookmarks,
                              child: ListTile(
                                leading: Icon(Icons.bookmarks_outlined),
                                title: Text('Marcadores'),
                              ),
                            ),
                          const PopupMenuItem(
                            value: _WorkspaceMoreAction.readingMode,
                            child: ListTile(
                              leading: Icon(Icons.fullscreen_outlined),
                              title: Text('Modo leitura em tela cheia'),
                              subtitle: Text('Ctrl+H'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _WorkspaceMoreAction.forms,
                            child: ListTile(
                              leading: Icon(Icons.checklist_outlined),
                              title: Text('Formulários'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _WorkspaceMoreAction.export,
                            child: ListTile(
                              leading: Icon(Icons.ios_share_outlined),
                              title: Text('Exportar PDF'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _WorkspaceMoreAction.print,
                            child: ListTile(
                              leading: Icon(Icons.print_outlined),
                              title: Text('Imprimir'),
                            ),
                          ),
                        ],
                        icon: const Icon(Icons.more_horiz),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _fitToolbarRow(double width, List<Widget> children) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarCommandButton({
    required bool compact,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }
    return _CommandButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
    );
  }

  Widget _stylusButton(
    _StylusMode mode,
    IconData icon,
    String label, {
    bool compact = false,
  }) {
    final selected = _stylusMode == mode;
    if (compact) {
      return IconButton(
        tooltip: label,
        isSelected: selected,
        onPressed: () => _setStylusMode(mode),
        icon: Icon(icon),
        selectedIcon: Icon(icon),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: selected
          ? FilledButton.tonalIcon(
              onPressed: () => _setStylusMode(mode),
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: () => _setStylusMode(mode),
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
  }

  void _setStylusMode(_StylusMode mode) {
    if (_stylusMode == mode) return;

    if ((mode == _StylusMode.selectText ||
            mode == _StylusMode.pen ||
            mode == _StylusMode.highlighter ||
            mode == _StylusMode.eraser ||
            mode == _StylusMode.note) &&
        _controller.isReady) {
      // Entering a modal tool freezes residual navigation immediately.
      _controller.stopInteractiveViewerAnimation();
    }

    if (_hasTextSelection &&
        mode != _StylusMode.hand &&
        mode != _StylusMode.selectText &&
        _controller.isReady) {
      unawaited(_controller.textSelectionDelegate.clearTextSelection());
    }

    setState(() => _stylusMode = mode);
    _controller.invalidate();
  }

  void _requestFullScreen() {
    final callback = widget.onToggleFullScreen;
    if (callback != null) {
      callback();
      return;
    }
    _toggleReadingMode();
  }

  void _toggleReadingMode() {
    unawaited(_setReadingMode(!_readingMode));
  }

  Future<void> _setReadingMode(bool enabled) async {
    if (!mounted || _readingMode == enabled) return;
    final preservedPage = _controller.pageNumber ?? _page;
    _chromeTransitionPage = preservedPage;
    setState(() {
      _readingMode = enabled;
      if (enabled) {
        // Reading mode is navigation-only so an invisible annotation tool
        // cannot capture the next tap while every toolbar is hidden.
        _stylusMode = _StylusMode.hand;
      }
    });
    _controller.invalidate();
    _schedulePageRestoreAfterChromeChange(preservedPage);

    if (_android) {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  Future<void> _loadInkCount() async {
    final count = await _inkStore.countForDocument(widget.document.id);
    if (mounted) setState(() => _inkCount = count);
  }

  Future<void> _loadInkWindow(PdfDocument document, int pageNumber) async {
    final generation = ++_inkLoadGeneration;
    final window = HugePdfPolicy.overlayWindow(
      pageNumber: pageNumber,
      pageCount: document.pages.length,
    );
    if (window.end < window.start) return;
    if (mounted) setState(() => _loadingInk = true);
    try {
      final strokes = await _inkStore.listForPageRange(
        widget.document.id,
        window.start,
        window.end,
      );
      final byPage = <int, List<PdfInkStroke>>{};
      for (final stroke in strokes) {
        byPage
            .putIfAbsent(stroke.pageNumber, () => <PdfInkStroke>[])
            .add(stroke);
      }
      if (!mounted || generation != _inkLoadGeneration) return;
      setState(() {
        _inkByPage.removeWhere(
          (page, _) => page < window.start || page > window.end,
        );
        for (var page = window.start; page <= window.end; page++) {
          final pageStrokes = byPage[page];
          if (pageStrokes == null || pageStrokes.isEmpty) {
            _inkByPage.remove(page);
          } else {
            _inkByPage[page] = pageStrokes;
          }
        }
      });
      _controller.invalidate();
    } finally {
      if (mounted && generation == _inkLoadGeneration) {
        setState(() => _loadingInk = false);
      }
    }
  }

  void _onStrokeCompleted(PdfInkStroke stroke) {
    setState(() {
      _inkByPage
          .putIfAbsent(stroke.pageNumber, () => <PdfInkStroke>[])
          .add(stroke);
      _inkCount++;
    });
    unawaited(_inkStore.addStroke(stroke));
    _controller.invalidate();
  }

  void _onEraseApplied(PdfInkEraseResult result) {
    final strokes = _inkByPage[result.original.pageNumber];
    if (strokes == null) return;
    final index = strokes.indexWhere(
      (stroke) => stroke.id == result.original.id,
    );
    if (index < 0) return;
    strokes
      ..removeAt(index)
      ..insertAll(index, result.fragments);
    if (strokes.isEmpty) _inkByPage.remove(result.original.pageNumber);
    setState(() {
      _inkCount = (_inkCount - 1 + result.fragments.length).clamp(0, 1 << 31);
    });
    unawaited(
      _inkStore.replaceStrokeWithFragments(result.original, result.fragments),
    );
    _controller.invalidate();
  }

  Future<void> _undoInk() async {
    final strokes = _inkByPage[_page];
    if (strokes == null || strokes.isEmpty) return;
    final removed = strokes.removeLast();
    if (strokes.isEmpty) _inkByPage.remove(_page);
    await _inkStore.deleteStroke(removed.id);
    if (!mounted) return;
    setState(() {
      if (_inkCount > 0) _inkCount--;
    });
    _controller.invalidate();
  }

  Future<void> _showInkSettings() async {
    var color = _inkColor;
    var width = _inkWidth;
    var eraserWidth = _eraserWidth;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'S Pen / Stylus',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'A pressão da caneta controla o traço. O botão lateral da S Pen funciona como atalho temporário para a borracha quando o Android reporta o botão ao Flutter.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final value in _palette)
                      InkWell(
                        onTap: () => setSheetState(() => color = value),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: value == color
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Espessura da caneta: ${width.toStringAsFixed(1)}'),
                Slider(
                  min: 1,
                  max: 10,
                  value: width,
                  onChanged: (value) => setSheetState(() => width = value),
                ),
                Text(
                  'Espessura da borracha: ${eraserWidth.toStringAsFixed(0)}',
                ),
                Slider(
                  min: 6,
                  max: 80,
                  divisions: 37,
                  value: eraserWidth,
                  onChanged: (value) =>
                      setSheetState(() => eraserWidth = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _inkColor = color;
                        _inkWidth = width;
                        _eraserWidth = eraserWidth;
                      });
                      _controller.invalidate();
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomMenu({bool compact = false}) {
    return PopupMenuButton<int>(
      tooltip: 'Definir zoom',
      onSelected: (value) {
        if (value == -1) {
          unawaited(_showCustomZoomDialog());
        } else {
          unawaited(_setZoomPercent(value));
        }
      },
      itemBuilder: (context) => [
        for (final value in _zoomPresets)
          PopupMenuItem(value: value, child: Text('$value%')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: -1, child: Text('Personalizado…')),
      ],
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 56 : 68),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_zoomPercent%'),
            if (!compact) ...[
              const SizedBox(width: 3),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  void _syncZoomFromController() {
    if (!_controller.isReady) return;
    final percent = (_controller.currentZoom * 100).round();
    if (!mounted || percent == _zoomPercent) return;
    setState(() => _zoomPercent = percent);
  }

  Offset _effectiveZoomLocalAnchor() {
    final anchor = _zoomAnchorLocal;
    if (anchor != null && anchor.dx.isFinite && anchor.dy.isFinite) {
      return anchor;
    }
    return _controller.documentToLocal(_controller.centerPosition);
  }

  Future<void> _setZoomPercent(int percent) async {
    if (!_controller.isReady) return;
    final target = (percent / 100)
        .clamp(_controller.minScale, _controller.maxScale)
        .toDouble();
    await _controller.zoomOnLocalPosition(
      localPosition: _effectiveZoomLocalAnchor(),
      newZoom: target,
      duration: Duration.zero,
    );
    _syncZoomFromController();
  }

  Future<void> _showCustomZoomDialog() async {
    final input = TextEditingController(text: '$_zoomPercent');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zoom personalizado'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Zoom (%)',
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(input.text.trim())),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null || value <= 0) return;
    await _setZoomPercent(value);
  }

  Future<void> _zoomIn() async {
    if (!_controller.isReady) return;
    await _controller.zoomUpOnLocalPosition(
      localPosition: _effectiveZoomLocalAnchor(),
    );
    _syncZoomFromController();
  }

  Future<void> _zoomOut() async {
    if (!_controller.isReady) return;
    await _controller.zoomDownOnLocalPosition(
      localPosition: _effectiveZoomLocalAnchor(),
    );
    _syncZoomFromController();
  }

  Future<void> _previousPage() async {
    if (!_controller.isReady || _page <= 1) return;
    await _controller.goToPage(
      pageNumber: _page - 1,
      anchor: PdfPageAnchor.top,
    );
  }

  Future<void> _nextPage() async {
    if (!_controller.isReady) return;
    final count = _document?.pages.length ?? _controller.pageCount;
    if (_page >= count) return;
    await _controller.goToPage(
      pageNumber: _page + 1,
      anchor: PdfPageAnchor.top,
    );
  }

  Future<void> _scrollBy(double deltaY) async {
    if (!_controller.isReady) return;
    final matrix = _controller.value.clone()
      ..multiply(Matrix4.translationValues(0.0, deltaY, 0.0));
    final safe = _controller.makeMatrixInSafeRange(matrix, forceClamp: true);
    await _controller.goTo(safe, duration: const Duration(milliseconds: 90));
  }

  Future<void> _openPageTools() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfPageToolsScreen(document: widget.document),
    ),
  );

  Future<void> _openOcr() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfOcrScreen(
        document: widget.document,
        navigationStore: widget.store,
      ),
    ),
  );

  void _handleMoreAction(_WorkspaceMoreAction action) {
    switch (action) {
      case _WorkspaceMoreAction.readingMode:
        _requestFullScreen();
      case _WorkspaceMoreAction.outline:
        if (_outline.isNotEmpty) unawaited(_showOutline());
      case _WorkspaceMoreAction.bookmarks:
        unawaited(_showBookmarks());
      case _WorkspaceMoreAction.forms:
        unawaited(_openForms());
      case _WorkspaceMoreAction.export:
        unawaited(_openExport());
      case _WorkspaceMoreAction.print:
        unawaited(_openPrint());
    }
  }

  Future<void> _openForms() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfFormsScreen(
        document: widget.document,
        store: LocalPdfFormStore(widget.store.db),
      ),
    ),
  );

  Future<void> _openExport() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PdfExportScreen(document: widget.document, db: widget.store.db),
    ),
  );

  Future<void> _openPrint() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PdfPrintScreen(
        document: widget.document,
        navigationStore: widget.store,
      ),
    ),
  );

  Future<void> _openExternalLink(Uri uri) async {
    if (!mounted) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http' && scheme != 'mailto') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Link bloqueado por segurança: $scheme')),
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abrir link externo?'),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }

  Future<void> _reloadBookmarks() async {
    final values = await widget.store.listBookmarks(widget.document.id);
    if (!mounted) return;
    setState(() => _bookmarks = values);
  }

  Future<void> _loadOutline(PdfDocument document) async {
    final values = await document.loadOutline();
    if (!mounted) return;
    setState(() => _outline = values);
  }

  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null) return;
    widget.onReaderActivity?.call();

    final transitionTarget = _chromeTransitionPage;
    if (transitionTarget != null && pageNumber != transitionTarget) {
      // Ignore the transient first-page callback emitted while the viewport is
      // being rebuilt for immersive mode. The preserved page is restored on
      // the next settled frame.
      return;
    }
    if (transitionTarget == pageNumber) {
      _chromeTransitionPage = null;
    }

    if (pageNumber == _page) {
      widget.onPageChanged?.call(pageNumber);
      return;
    }
    final previous = _page;
    setState(() => _page = pageNumber);
    widget.onPageChanged?.call(pageNumber);
    final document = _document;
    if (document != null) unawaited(_loadInkWindow(document, pageNumber));
    if (_historyNavigation) {
      _historyNavigation = false;
      return;
    }
    if (_backHistory.isEmpty || _backHistory.last != previous) {
      _backHistory.add(previous);
      if (_backHistory.length > 100) _backHistory.removeAt(0);
    }
    _forwardHistory.clear();
  }

  Future<void> _goBack() async {
    if (_backHistory.isEmpty) return;
    final target = _backHistory.removeLast();
    _forwardHistory.add(_page);
    _historyNavigation = true;
    await _controller.goToPage(pageNumber: target, anchor: PdfPageAnchor.top);
    if (mounted) setState(() {});
  }

  Future<void> _goForward() async {
    if (_forwardHistory.isEmpty) return;
    final target = _forwardHistory.removeLast();
    _backHistory.add(_page);
    _historyNavigation = true;
    await _controller.goToPage(pageNumber: target, anchor: PdfPageAnchor.top);
    if (mounted) setState(() {});
  }

  Future<void> _jumpToPage() async {
    final input = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ir para página'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Número da página'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(input.text)),
            child: const Text('Ir'),
          ),
        ],
      ),
    );
    input.dispose();
    if (page == null || page < 1) return;
    final maxPage = _document?.pages.length;
    if (maxPage != null && page > maxPage) return;
    await _controller.goToPage(pageNumber: page, anchor: PdfPageAnchor.top);
  }

  Future<void> _toggleCurrentBookmark() async {
    await widget.store.toggleBookmark(
      documentId: widget.document.id,
      pageNumber: _page,
    );
    await _reloadBookmarks();
  }

  Future<void> _showBookmarks() async {
    final values = await widget.store.listBookmarks(widget.document.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: values.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('Nenhum marcador criado.')),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: values.length,
                itemBuilder: (context, index) {
                  final bookmark = values[index];
                  return ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(bookmark.label),
                    subtitle: Text('Página ${bookmark.pageNumber}'),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(
                        _controller.goToPage(
                          pageNumber: bookmark.pageNumber,
                          anchor: PdfPageAnchor.top,
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showOutline() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [for (final node in _outline) _outlineTile(node, 0)],
          ),
        ),
      ),
    );
  }

  Widget _outlineTile(PdfOutlineNode node, int depth) {
    final children = node.children;
    if (children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: 12.0 + depth * 18, right: 8),
        title: Text(node.title),
        subtitle: node.dest == null
            ? null
            : Text('Página ${node.dest!.pageNumber}'),
        onTap: node.dest == null
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_controller.goToDest(node.dest));
              },
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: 12.0 + depth * 18, right: 8),
      title: Text(node.title),
      subtitle: node.dest == null
          ? null
          : Text('Página ${node.dest!.pageNumber}'),
      children: [for (final child in children) _outlineTile(child, depth + 1)],
    );
  }

  Future<void> _showThumbnails(String path) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: PdfDocumentViewBuilder.file(
            path,
            builder: (context, document) {
              if (document == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: 230,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: document.pages.length,
                itemBuilder: (context, index) {
                  final pageNumber = index + 1;
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(
                        _controller.goToPage(
                          pageNumber: pageNumber,
                          anchor: PdfPageAnchor.top,
                        ),
                      );
                    },
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Expanded(
                            child: PdfPageView(
                              document: document,
                              pageNumber: pageNumber,
                              maximumDpi: 110,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text('Página $pageNumber'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  PdfPageLayout _horizontalLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height =
        pages.fold<double>(
          0,
          (previous, page) => math.max(previous, page.height),
        ) +
        params.margin * 2;
    final layouts = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      layouts.add(
        Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height),
      );
      x += page.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: layouts, documentSize: Size(x, height));
  }

  PdfPageLayout _facingLayout(List<PdfPage> pages, PdfViewerParams params) {
    final maxWidth = pages.fold<double>(
      0,
      (previous, page) => math.max(previous, page.width),
    );
    final layouts = <Rect>[];
    var y = params.margin;
    for (var i = 0; i < pages.length; i += 2) {
      final left = pages[i];
      final right = i + 1 < pages.length ? pages[i + 1] : null;
      final rowHeight = math.max(left.height, right?.height ?? 0);
      layouts.add(
        Rect.fromLTWH(
          params.margin + maxWidth - left.width,
          y + (rowHeight - left.height) / 2,
          left.width,
          left.height,
        ),
      );
      if (right != null) {
        layouts.add(
          Rect.fromLTWH(
            params.margin * 2 + maxWidth,
            y + (rowHeight - right.height) / 2,
            right.width,
            right.height,
          ),
        );
      }
      y += rowHeight + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(params.margin * 3 + maxWidth * 2, y),
    );
  }
}

class _SelectionMarkupOverlayPainter extends CustomPainter {
  const _SelectionMarkupOverlayPainter({
    required this.menu,
    required this.pageRect,
    required this.page,
  });

  final PdfSelectionActionMenu menu;
  final Rect pageRect;
  final PdfPage page;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-pageRect.left, -pageRect.top);
    menu.paint(canvas, pageRect, page);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SelectionMarkupOverlayPainter oldDelegate) =>
      true;
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
