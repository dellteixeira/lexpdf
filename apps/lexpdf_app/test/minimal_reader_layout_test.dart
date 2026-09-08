import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/theme/lexpdf_theme.dart';
import 'package:lexpdf_app/src/widgets/pdf_reader_controls.dart';

void main() {
  Widget harness({
    required Size size,
    required VoidCallback onStudy,
  }) {
    return MaterialApp(
      theme: LexPdfTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Documento'),
            actions: [
              PdfReaderAppBarActions(
                currentPage: 42,
                inkMode: false,
                inkEraserMode: false,
                annotationCount: 7,
                inkCount: 3,
                onToggleInkMode: () {},
                onToggleEraser: () {},
                onConfigureInk: () {},
                onUndoInk: () {},
                onOpenStudy: onStudy,
                onOpenSearch: () {},
                onOpenAnnotationPalette: () {},
                onOpenAnnotations: () {},
                onOpenInkSummary: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  test('minimal theme keeps surfaces flat and compact', () {
    final light = LexPdfTheme.light;
    final dark = LexPdfTheme.dark;

    expect(light.useMaterial3, isTrue);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF6F7F9));
    expect(light.appBarTheme.toolbarHeight, 56);
    expect(light.appBarTheme.elevation, 0);
    expect(light.cardTheme.elevation, 0);
    expect(dark.brightness, Brightness.dark);
  });

  testWidgets('mobile reader keeps primary actions visible and moves extras to overflow',
      (tester) async {
    var studyCalls = 0;
    await tester.pumpWidget(
      harness(
        size: const Size(390, 844),
        onStudy: () => studyCalls++,
      ),
    );

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
    expect(find.text('42'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Estudar documento'), findsOneWidget);
    expect(find.text('Anotações textuais · 7'), findsOneWidget);

    await tester.tap(find.text('Estudar documento'));
    await tester.pumpAndSettle();
    expect(studyCalls, 1);
  });

  testWidgets('desktop reader exposes direct tools without mobile overflow',
      (tester) async {
    await tester.pumpWidget(
      harness(
        size: const Size(1440, 900),
        onStudy: () {},
      ),
    );

    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byIcon(Icons.draw_outlined), findsOneWidget);
    expect(find.byIcon(Icons.gesture_outlined), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
