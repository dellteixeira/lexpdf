import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    expect(workspace, contains('PdfViewer.file('));
    expect(workspace, contains('useProgressiveLoading: true'));
    expect(workspace, contains('controller.zoomUp()'));
    expect(workspace, contains('controller.zoomDown()'));
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
