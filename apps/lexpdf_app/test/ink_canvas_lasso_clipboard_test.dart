import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/widgets/ink_canvas.dart';

void main() {
  InkStroke stroke() => InkStroke(
        id: 'source',
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF246BFD,
        opacity: 1,
        width: 3,
        points: const [
          InkPoint(x: 30, y: 30, pressure: 0.6, tilt: 0.2, timestampMicros: 1),
          InkPoint(x: 50, y: 50, pressure: 0.8, tilt: 0.3, timestampMicros: 2),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      );

  Future<GlobalKey<InkCanvasState>> pumpCanvas(
    WidgetTester tester, {
    required List<InkStroke> completed,
    required List<InkStroke> erased,
  }) async {
    final key = GlobalKey<InkCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: InkCanvas(
              key: key,
              initialStrokes: [stroke()],
              pageId: 'page-1',
              tool: InkTool.pen,
              colorValue: 0xFF000000,
              strokeWidth: 3,
              lassoMode: true,
              stylusOnly: false,
              onStrokeCompleted: completed.add,
              onStrokeErased: erased.add,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(10, 10));
    await gesture.moveTo(const Offset(100, 10));
    await gesture.moveTo(const Offset(100, 100));
    await gesture.moveTo(const Offset(10, 100));
    await gesture.moveTo(const Offset(10, 10));
    await gesture.up();
    await tester.pump();
    return key;
  }

  testWidgets('copiar e colar cria novos ids, desloca e persiste via callback', (tester) async {
    final completed = <InkStroke>[];
    final erased = <InkStroke>[];
    final key = await pumpCanvas(tester, completed: completed, erased: erased);

    final copied = key.currentState!.copySelected();
    expect(copied.single.id, 'source');
    expect(key.currentState!.hasClipboard, isTrue);

    final pasted = key.currentState!.pasteClipboard();
    expect(pasted, hasLength(1));
    expect(pasted.single.id, isNot('source'));
    expect(pasted.single.points.first.x, 46);
    expect(pasted.single.points.first.y, 46);
    expect(pasted.single.points.first.pressure, 0.6);
    expect(completed.single.id, pasted.single.id);
    expect(erased, isEmpty);
    expect(key.currentState!.selectedStrokeIds, {pasted.single.id});
  });

  testWidgets('duplicar e recortar usam callbacks de persistência', (tester) async {
    final completed = <InkStroke>[];
    final erased = <InkStroke>[];
    final key = await pumpCanvas(tester, completed: completed, erased: erased);

    final duplicated = key.currentState!.duplicateSelected();
    expect(duplicated, hasLength(1));
    expect(duplicated.single.id, isNot('source'));
    expect(completed.single.id, duplicated.single.id);

    final cut = key.currentState!.cutSelected();
    expect(cut, hasLength(1));
    expect(cut.single.id, duplicated.single.id);
    expect(erased.single.id, duplicated.single.id);
    expect(key.currentState!.hasClipboard, isTrue);
    expect(key.currentState!.selectedStrokeIds, isEmpty);

    final repasted = key.currentState!.pasteClipboard();
    expect(repasted, hasLength(1));
    expect(repasted.single.id, isNot(duplicated.single.id));
    expect(completed, hasLength(2));
  });
}
