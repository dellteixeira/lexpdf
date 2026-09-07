import 'package:flutter/material.dart';

import '../core/documents/document_provider.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'pdf_advanced_annotation_screen.dart';
import 'pdf_navigation_screen.dart';
import 'pdf_ocr_screen.dart';
import 'pdf_page_tools_screen.dart';
import 'pdf_reader_screen.dart';

class PdfWorkspaceScreen extends StatefulWidget {
  const PdfWorkspaceScreen({
    required this.document,
    required this.readingProgress,
    required this.annotations,
    required this.pdfInkStore,
    super.key,
  });

  final DocumentRef document;
  final LocalReadingProgressStore readingProgress;
  final LocalTextAnnotationStore annotations;
  final LocalPdfInkStore pdfInkStore;

  @override
  State<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends State<PdfWorkspaceScreen> {
  int _selectedIndex = 0;
  final Map<int, Widget> _loadedViews = <int, Widget>{};

  LocalPdfNavigationStore get _navigationStore =>
      LocalPdfNavigationStore(widget.annotations.db);

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: 'Ler',
    ),
    NavigationDestination(
      icon: Icon(Icons.navigation_outlined),
      selectedIcon: Icon(Icons.navigation),
      label: 'Navegar',
    ),
    NavigationDestination(
      icon: Icon(Icons.draw_outlined),
      selectedIcon: Icon(Icons.draw),
      label: 'Anotar',
    ),
    NavigationDestination(
      icon: Icon(Icons.edit_document),
      selectedIcon: Icon(Icons.edit_document),
      label: 'Páginas',
    ),
    NavigationDestination(
      icon: Icon(Icons.document_scanner_outlined),
      selectedIcon: Icon(Icons.document_scanner),
      label: 'OCR',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadedViews[0] = _buildView(0);
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _loadedViews.putIfAbsent(index, () => _buildView(index));
    });
  }

  Widget _buildView(int index) {
    switch (index) {
      case 1:
        return PdfNavigationScreen(
          document: widget.document,
          store: _navigationStore,
        );
      case 2:
        return PdfAdvancedAnnotationScreen(
          document: widget.document,
          annotations: widget.annotations,
        );
      case 3:
        return PdfPageToolsScreen(document: widget.document);
      case 4:
        return PdfOcrScreen(
          document: widget.document,
          navigationStore: _navigationStore,
        );
      case 0:
      default:
        return PdfReaderScreen(
          document: widget.document,
          readingProgress: widget.readingProgress,
          annotations: widget.annotations,
          pdfInkStore: widget.pdfInkStore,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final activeView = _loadedViews[_selectedIndex] ?? _buildView(_selectedIndex);

    if (compact) {
      return Scaffold(
        body: activeView,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _select,
          destinations: _destinations,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Tooltip(
                  message: widget.document.name,
                  child: const Icon(Icons.picture_as_pdf_outlined, size: 30),
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: Text('Ler'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.navigation_outlined),
                  selectedIcon: Icon(Icons.navigation),
                  label: Text('Navegar'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.draw_outlined),
                  selectedIcon: Icon(Icons.draw),
                  label: Text('Anotar'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.edit_document),
                  selectedIcon: Icon(Icons.edit_document),
                  label: Text('Páginas'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.document_scanner_outlined),
                  selectedIcon: Icon(Icons.document_scanner),
                  label: Text('OCR'),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: activeView),
        ],
      ),
    );
  }
}
