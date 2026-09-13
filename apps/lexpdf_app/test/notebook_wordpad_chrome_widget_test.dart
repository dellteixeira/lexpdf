import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/widgets/notebook_wordpad_chrome.dart';

void main() {
  Widget buildSubject() {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 800,
          child: NotebookWordPadScaffold(
            title: 'Caderno de teste',
            homeRibbon: const Center(child: Text('HOME-RIBBON')),
            drawingRibbon: const Center(child: Text('DRAWING-RIBBON')),
            viewRibbon: const Center(child: Text('VIEW-RIBBON')),
            document: const ColoredBox(color: Colors.white),
            pageIndex: 0,
            pageCount: 3,
            wordCount: 42,
            layerName: 'Camada 1',
            zoom: 1,
            showDocumentRuler: true,
            onNewNotebook: () {},
            onRenameNotebook: () {},
            onDeleteNotebook: () {},
            onNewPage: () {},
            onDuplicatePage: () {},
            onDeletePage: () {},
            onLayers: () {},
            onPreviousPage: null,
            onNextPage: () {},
            onUndo: () {},
            onRedo: () {},
            onZoomChanged: (_) {},
            onFitPage: () {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'uses desktop WordPad chrome and fixed ruler/status proportions',
    (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('Arquivo'), findsOneWidget);
      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Desenho'), findsOneWidget);
      expect(find.text('Exibir'), findsOneWidget);
      expect(find.text('Caderno de teste — LexPDF'), findsOneWidget);
      expect(find.text('HOME-RIBBON'), findsOneWidget);
      expect(find.byType(NotebookDocumentRuler), findsOneWidget);
      expect(find.byType(NotebookWordPadStatusBar), findsOneWidget);
      expect(tester.getSize(find.byType(NotebookDocumentRuler)).height, 25);
      expect(tester.getSize(find.byType(NotebookWordPadStatusBar)).height, 29);
      expect(find.text('Página 1 de 3'), findsOneWidget);
      expect(find.text('Palavras: 42'), findsOneWidget);
    },
  );

  testWidgets('switches ribbon content without stacking mobile toolbars', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('Desenho'));
    await tester.pump();
    expect(find.text('HOME-RIBBON'), findsNothing);
    expect(find.text('DRAWING-RIBBON'), findsOneWidget);

    await tester.tap(find.text('Exibir'));
    await tester.pump();
    expect(find.text('DRAWING-RIBBON'), findsNothing);
    expect(find.text('VIEW-RIBBON'), findsOneWidget);

    await tester.tap(find.text('Início'));
    await tester.pump();
    expect(find.text('VIEW-RIBBON'), findsNothing);
    expect(find.text('HOME-RIBBON'), findsOneWidget);
  });
}
