import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';
import 'package:flutter/material.dart';

import 'notebook_two_finger_navigation_region.dart';

class NotebookRichDocumentSurface extends StatefulWidget {
  const NotebookRichDocumentSurface({
    required this.document,
    required this.enabled,
    super.key,
  });

  final FluentDocument document;
  final bool enabled;

  @override
  State<NotebookRichDocumentSurface> createState() =>
      _NotebookRichDocumentSurfaceState();
}

class _NotebookRichDocumentSurfaceState
    extends State<NotebookRichDocumentSurface> {
  bool _twoFingerNavigating = false;
  bool _restoreFocusAfterNavigation = false;

  @override
  void initState() {
    super.initState();
    widget.document.registry.attach(widget.document);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.document.requestEditorFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant NotebookRichDocumentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      oldWidget.document.registry.detach(oldWidget.document);
      widget.document.registry.attach(widget.document);
    }
    if (oldWidget.enabled == widget.enabled &&
        identical(oldWidget.document, widget.document)) {
      return;
    }
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_twoFingerNavigating) {
          widget.document.requestEditorFocus();
        }
      });
    } else {
      widget.document.editorFocusNode.unfocus();
    }
  }

  @override
  void dispose() {
    widget.document.registry.detach(widget.document);
    super.dispose();
  }

  void _onTwoFingerNavigationChanged(bool active) {
    if (_twoFingerNavigating == active) return;
    if (active) {
      _restoreFocusAfterNavigation = widget.document.editorFocusNode.hasFocus;
      widget.document.editorFocusNode.unfocus();
    }
    setState(() => _twoFingerNavigating = active);
    if (!active && _restoreFocusAfterNavigation && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled && !_twoFingerNavigating) {
          widget.document.requestEditorFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The document is paper, not application chrome. Force a light editor
    // palette even when LexPDF itself is running with a dark theme so text,
    // caret and selection keep Word/WordPad semantics on the white page.
    final editorTheme = ThemeData.light(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF2F66B3),
        onPrimary: Colors.white,
        surface: Colors.transparent,
        onSurface: Color(0xFF202124),
        surfaceContainerHighest: Color(0xFFF3F5F8),
        outline: Color(0xFFB8BEC7),
      ),
    );
    return NotebookTwoFingerNavigationRegion(
      active: widget.enabled,
      onNavigationChanged: _onTwoFingerNavigationChanged,
      child: IgnorePointer(
        ignoring: !widget.enabled || _twoFingerNavigating,
        child: FocusScope(
          canRequestFocus: widget.enabled && !_twoFingerNavigating,
          descendantsAreFocusable: widget.enabled && !_twoFingerNavigating,
          child: Theme(
            data: editorTheme,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // FluentDocumentWidget includes its own bottom-right diagnostics
                // button. Give the child a larger clipped viewport so that package
                // chrome falls outside the LexPDF paper while keeping its complete
                // caret/IME/selection implementation intact.
                final extendedHeight = constraints.maxHeight + 72;
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: extendedHeight,
                    maxHeight: extendedHeight,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: extendedHeight,
                      child: KeyedSubtree(
                        key: ValueKey(
                          'fluent-document-${widget.document.hashCode}-${_twoFingerNavigating ? 'navigation' : 'editing'}',
                        ),
                        child: FluentDocumentWidget(
                          document: widget.document,
                          maxWidth: constraints.maxWidth,
                          toolbarMode: FluentToolbarMode.bubble,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
