import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sticky notes support hold-drag repositioning and cross-page drops', () {
    final overlay = File(
      'lib/src/widgets/pdf_sticky_note_overlay.dart',
    ).readAsStringSync();
    final model = File(
      'lib/src/core/annotations/pdf_annotation_object.dart',
    ).readAsStringSync();
    final store = File(
      'lib/src/core/storage/local_pdf_annotation_object_store.dart',
    ).readAsStringSync();

    expect(overlay, contains('LongPressDraggable<_StickyNoteDragData>'));
    expect(overlay, contains('DragTarget<_StickyNoteDragData>'));
    expect(overlay, contains('Segure e arraste para mover'));
    expect(overlay, contains('delay: const Duration(milliseconds: 280)'));
    expect(overlay, contains('onAcceptWithDetails'));
    expect(overlay, contains('_acceptDrop'));
    expect(overlay, contains('_maybeAutoScroll'));
    expect(overlay, contains('Scrollable.maybeOf(context)'));
    expect(overlay, contains('pageNumber: widget.pageNumber'));
    expect(overlay, contains('widget.store.upsert(moved)'));
    expect(overlay, contains('.clamp(0.0, 1.0 - source.width)'));
    expect(overlay, contains('.clamp(0.0, 1.0 - source.height)'));

    expect(model, contains('int? pageNumber,'));
    expect(model, contains('pageNumber: pageNumber ?? this.pageNumber'));
    expect(store, contains('page_number = excluded.page_number'));
  });
}
