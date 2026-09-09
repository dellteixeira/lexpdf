import '../ink/ink_models.dart';
import 'notebook_object_models.dart';

class NotebookPageSnapshot {
  const NotebookPageSnapshot({
    required this.strokes,
    required this.objects,
    this.strokeLayerIds = const {},
    this.objectLayerIds = const {},
  });

  final List<InkStroke> strokes;
  final List<NotebookObject> objects;
  final Map<String, String> strokeLayerIds;
  final Map<String, String> objectLayerIds;

  factory NotebookPageSnapshot.capture({
    required List<InkStroke> strokes,
    required List<NotebookObject> objects,
    Map<String, String> strokeLayerIds = const {},
    Map<String, String> objectLayerIds = const {},
  }) {
    return NotebookPageSnapshot(
      strokes: List<InkStroke>.unmodifiable(strokes),
      objects: List<NotebookObject>.unmodifiable(objects),
      strokeLayerIds: Map<String, String>.unmodifiable(strokeLayerIds),
      objectLayerIds: Map<String, String>.unmodifiable(objectLayerIds),
    );
  }
}

class NotebookHistoryController {
  NotebookHistoryController({int limit = 80}) : limit = limit < 10 ? 10 : limit;

  /// Safety floor: the notebook must always preserve at least ten undo states.
  /// The application default remains 80 states for comfortable editing sessions.
  final int limit;
  final List<NotebookPageSnapshot> _undo = [];
  final List<NotebookPageSnapshot> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  void record(NotebookPageSnapshot snapshot) {
    _undo.add(snapshot);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  NotebookPageSnapshot? undo(NotebookPageSnapshot current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    if (_redo.length > limit) _redo.removeAt(0);
    return _undo.removeLast();
  }

  NotebookPageSnapshot? redo(NotebookPageSnapshot current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    if (_undo.length > limit) _undo.removeAt(0);
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
