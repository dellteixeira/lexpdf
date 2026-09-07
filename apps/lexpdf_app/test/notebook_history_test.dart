import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/notebook/notebook_history.dart';
import 'package:lexpdf_app/src/core/notebook/notebook_object_models.dart';

void main() {
  InkStroke stroke(String id) => InkStroke(
        id: id,
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF000000,
        opacity: 1,
        width: 3,
        points: const [
          InkPoint(x: 0, y: 0, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 10, y: 10, pressure: 1, tilt: 0, timestampMicros: 2),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      );

  NotebookObject object(String id) => NotebookObject(
        id: id,
        pageId: 'page-1',
        type: NotebookObjectType.rectangle,
        x: 10,
        y: 10,
        width: 50,
        height: 40,
        rotation: 0,
        colorValue: 0xFF000000,
        strokeWidth: 2,
        createdAt: DateTime.utc(2026, 9, 6),
        updatedAt: DateTime.utc(2026, 9, 6),
      );

  test('undo and redo restore composite page snapshots', () {
    final history = NotebookHistoryController();
    final empty = NotebookPageSnapshot.capture(strokes: const [], objects: const []);
    final withStroke = NotebookPageSnapshot.capture(strokes: [stroke('s1')], objects: const []);
    final withBoth = NotebookPageSnapshot.capture(strokes: [stroke('s1')], objects: [object('o1')]);

    history.record(empty);
    history.record(withStroke);

    final undo = history.undo(withBoth)!;
    expect(undo.strokes, hasLength(1));
    expect(undo.objects, isEmpty);
    expect(history.canRedo, isTrue);

    final redo = history.redo(undo)!;
    expect(redo.objects, hasLength(1));
    expect(redo.objects.single.id, 'o1');
  });

  test('new record clears redo history', () {
    final history = NotebookHistoryController();
    final empty = NotebookPageSnapshot.capture(strokes: const [], objects: const []);
    final first = NotebookPageSnapshot.capture(strokes: [stroke('s1')], objects: const []);
    history.record(empty);
    history.undo(first);
    expect(history.canRedo, isTrue);
    history.record(first);
    expect(history.canRedo, isFalse);
  });
}
