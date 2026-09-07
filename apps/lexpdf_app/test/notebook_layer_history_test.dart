import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/notebook/notebook_history.dart';
import 'package:lexpdf_app/src/core/notebook/notebook_object_models.dart';

void main() {
  test('notebook history preserves stroke and object layer mappings', () {
    final now = DateTime.utc(2026, 9, 6);
    final stroke = InkStroke(
      id: 'stroke-1',
      pageId: 'page-1',
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: 2,
      points: const [InkPoint(x: 1, y: 2, pressure: 1, tilt: 0, timestampMicros: 1)],
      createdAt: now,
    );
    final object = NotebookObject(
      id: 'object-1',
      pageId: 'page-1',
      type: NotebookObjectType.rectangle,
      x: 1,
      y: 2,
      width: 30,
      height: 40,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    );

    final snapshot = NotebookPageSnapshot.capture(
      strokes: [stroke],
      objects: [object],
      strokeLayerIds: const {'stroke-1': 'layer-a'},
      objectLayerIds: const {'object-1': 'layer-b'},
    );

    expect(snapshot.strokeLayerIds['stroke-1'], 'layer-a');
    expect(snapshot.objectLayerIds['object-1'], 'layer-b');
    expect(() => snapshot.strokeLayerIds['x'] = 'y', throwsUnsupportedError);
  });
}
