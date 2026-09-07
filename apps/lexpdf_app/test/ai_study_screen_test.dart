import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ai/ai_models.dart';
import 'package:lexxpdf_app/src/screens/ai_study_screen.dart';

void main() {
  testWidgets('autoruns an initial selected-text action offline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AiStudyScreen(
          initialText: 'A publicidade favorece transparência e controle social.',
          initialAction: AiStudyAction.summarize,
          autorun: true,
          title: 'Estudar seleção',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Resultado'), findsOneWidget);
    expect(find.text('Local/offline'), findsOneWidget);
  });
}
