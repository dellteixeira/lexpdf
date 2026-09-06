import '../ink/ink_models.dart';
import 'notebook_object_models.dart';

class NotebookPageSnapshot {
  const NotebookPageSnapshot({
    required this.strokes,
    required this.objects,
  });

  final List<InkStroke> strokes;
  final List<NotebookObject> objects;

  factory NotebookPageSnapshot.capture({
    required List<InkStroke> strokes,
    required List<NotebookObject> objects,
  }) {
    return NotebookPageSnapshot(
      strokes: List<InkStroke>.unmodifiable(strokes),
      objects: List<NotebookObject>.unmodifiable(objects),
    );
  }
}

class NotebookHistoryController {
  NotebookHistoryController({this.limit = 80});

  final int limit;
  final List<NotebookPageSnapshot> _undo = [];
  final List<NotebookPageSnapshot> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void record(NotebookPageSnapshot snapshot) {
    _undo.add(snapshot);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  NotebookPageSnapshot? undo(NotebookPageSnapshot current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  NotebookPageSnapshot? redo(NotebookPageSnapshot current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
