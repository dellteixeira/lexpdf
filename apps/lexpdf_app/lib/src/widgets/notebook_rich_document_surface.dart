import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';
import 'package:flutter/material.dart';

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
  @override
  void didUpdateWidget(covariant NotebookRichDocumentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) return;
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.document.requestEditorFocus();
      });
    } else {
      widget.document.editorFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme.copyWith(
      surface: Colors.transparent,
    );
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: FocusScope(
        canRequestFocus: widget.enabled,
        descendantsAreFocusable: widget.enabled,
        child: Theme(
          data: Theme.of(context).copyWith(colorScheme: scheme),
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
                    child: FluentDocumentWidget(
                      document: widget.document,
                      maxWidth: constraints.maxWidth,
                      toolbarMode: FluentToolbarMode.bubble,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
