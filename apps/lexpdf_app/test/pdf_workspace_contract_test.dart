import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _workspaceSource() {
  final entrypoint =
      File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
  final implementation = File(
    'lib/src/screens/pdf_workspace_stylus_screen.dart',
  ).readAsStringSync();
  return '$entrypoint\n$implementation';
}

void main() {
  test('library exposes one primary PDF workspace entry point', () {
    final library = File('lib/src/screens/library_screen.dart').readAsStringSync();

    expect(library, contains("title: 'Trabalhar com PDF'"));
    expect(library, contains('PdfWorkspaceScreen('));
    expect(library, isNot(contains("title: 'Navegação avançada'")));
    expect(library, isNot(contains("title: 'Anotar PDF'")));
    expect(library, isNot(contains("title: 'Editar páginas'")));
  });

  test('workspace groups navigation editing OCR and zoom controls', () {
    final workspace = _workspaceSource();

    expect(workspace, contains("export 'pdf_workspace_stylus_screen.dart';"));
    expect(workspace, contains('PdfViewer.file('));
    expect(workspace, contains('useProgressiveLoading: !_windows'));
    expect(workspace, contains('_controller.zoomUp()'));
    expect(workspace, contains('_controller.zoomDown()'));
    expect(workspace, contains("label: 'Miniaturas'"));
    expect(workspace, contains("label: 'Sumário'"));
    expect(workspace, contains("label: 'Marcadores'"));
    expect(workspace, contains("label: 'Anotar'"));
    expect(workspace, contains("label: 'Páginas'"));
    expect(workspace, contains("label: 'OCR'"));
    expect(workspace, contains('PdfAdvancedAnnotationScreen('));
    expect(workspace, contains('PdfPageToolsScreen('));
    expect(workspace, contains('PdfOcrScreen('));
    expect(workspace, contains('PdfFormsScreen('));
    expect(workspace, contains('PdfExportScreen('));
    expect(workspace, contains('PdfPrintScreen('));
  });
}
