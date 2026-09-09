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

  NotebookPageSnapshot snapshot(int index) => NotebookPageSnapshot.capture(
        strokes: [stroke('s-$index')],
        objects: [object('o-$index')],
        strokeLayerIds: {'s-$index': 'layer-${index % 12}'},
        objectLayerIds: {'o-$index': 'layer-${(index + 5) % 12}'},
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

  test('history always preserves at least ten undo states', () {
    final history = NotebookHistoryController(limit: 1);
    expect(history.limit, 10);

    for (var index = 0; index < 12; index++) {
      history.record(snapshot(index));
    }

    expect(history.undoDepth, 10);
    var current = snapshot(12);
    var undoCount = 0;
    while (history.canUndo) {
      current = history.undo(current)!;
      undoCount += 1;
    }

    expect(undoCount, 10);
    expect(history.redoDepth, 10);
  });

  test('long undo/redo cycle stays bounded and preserves layer assignments', () {
    const limit = 80;
    final history = NotebookHistoryController(limit: limit);

    for (var index = 0; index < 100; index++) {
      history.record(snapshot(index));
    }

    var current = snapshot(100);
    final undone = <int>[];
    while (history.canUndo) {
      final previous = history.undo(current);
      expect(previous, isNotNull);
      current = previous!;
      final index = int.parse(current.objects.single.id.substring(2));
      undone.add(index);
      expect(current.strokeLayerIds[current.strokes.single.id], 'layer-${index % 12}');
      expect(current.objectLayerIds[current.objects.single.id], 'layer-${(index + 5) % 12}');
    }

    expect(undone, hasLength(limit));
    expect(undone.first, 99);
    expect(undone.last, 20);
    expect(history.undo(current), isNull);
    expect(history.canRedo, isTrue);

    final redone = <int>[];
    while (history.canRedo) {
      final next = history.redo(current);
      expect(next, isNotNull);
      current = next!;
      final index = int.parse(current.objects.single.id.substring(2));
      redone.add(index);
      expect(current.strokeLayerIds[current.strokes.single.id], 'layer-${index % 12}');
      expect(current.objectLayerIds[current.objects.single.id], 'layer-${(index + 5) % 12}');
    }

    expect(redone, hasLength(limit));
    expect(redone.first, 21);
    expect(redone.last, 100);
    expect(history.canUndo, isTrue);
    expect(history.redo(current), isNull);
  });

  test('captured snapshots do not change when source collections mutate', () {
    final strokes = <InkStroke>[stroke('stable-stroke')];
    final objects = <NotebookObject>[object('stable-object')];
    final strokeLayers = <String, String>{'stable-stroke': 'layer-a'};
    final objectLayers = <String, String>{'stable-object': 'layer-b'};

    final captured = NotebookPageSnapshot.capture(
      strokes: strokes,
      objects: objects,
      strokeLayerIds: strokeLayers,
      objectLayerIds: objectLayers,
    );

    strokes.clear();
    objects.clear();
    strokeLayers['stable-stroke'] = 'layer-c';
    objectLayers.clear();

    expect(captured.strokes.single.id, 'stable-stroke');
    expect(captured.objects.single.id, 'stable-object');
    expect(captured.strokeLayerIds['stable-stroke'], 'layer-a');
    expect(captured.objectLayerIds['stable-object'], 'layer-b');
    expect(() => captured.strokeLayerIds['x'] = 'layer-x', throwsUnsupportedError);
  });
}
