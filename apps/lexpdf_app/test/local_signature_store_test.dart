import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/annotations/saved_signature.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_signature_store.dart';

void main() {
  test('persists reusable vector signatures offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalSignatureStore(database);
    final now = DateTime.utc(2026, 9, 6);
    final signature = SavedSignature(
      id: 'sig-1',
      name: 'Principal',
      strokes: const [
        [
          SignaturePoint(0.1, 0.5),
          SignaturePoint(0.4, 0.2),
          SignaturePoint(0.9, 0.7),
        ],
      ],
      colorValue: 0xFF111111,
      strokeWidth: 3,
      createdAt: now,
      updatedAt: now,
    );

    await store.upsert(signature);
    final restored = await store.listAll();

    expect(restored, hasLength(1));
    expect(restored.single.name, 'Principal');
    expect(restored.single.strokes.single, hasLength(3));
    expect(restored.single.strokes.single[1].x, 0.4);
    expect(restored.single.strokeWidth, 3);
  });

  test('updates and deletes a saved signature without changing its id', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalSignatureStore(database);
    final now = DateTime.utc(2026, 9, 6);
    final signature = SavedSignature(
      id: 'sig-2',
      name: 'Rápida',
      strokes: const [
        [SignaturePoint(0, 0), SignaturePoint(1, 1)],
      ],
      colorValue: 0xFF111111,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    );

    await store.upsert(signature);
    await store.upsert(signature.copyWith(name: 'Contrato', strokeWidth: 4));
    final restored = await store.getById('sig-2');
    expect(restored?.name, 'Contrato');
    expect(restored?.strokeWidth, 4);

    await store.delete('sig-2');
    expect(await store.getById('sig-2'), isNull);
  });

  test('signature vector JSON is self contained for PDF placement', () {
    const strokes = [
      [SignaturePoint(0.2, 0.3), SignaturePoint(0.8, 0.7)],
    ];
    final encoded = SavedSignature.encodeStrokes(strokes);
    final decoded = SavedSignature.decodeStrokes(encoded);

    expect(decoded.single, hasLength(2));
    expect(decoded.single.first.x, 0.2);
    expect(decoded.single.last.y, 0.7);
  });

  test('rejects signatures without drawable strokes', () {
    final now = DateTime.utc(2026, 9, 6);
    final invalid = SavedSignature(
      id: 'invalid',
      name: 'Inválida',
      strokes: const [
        [SignaturePoint(0.5, 0.5)],
      ],
      colorValue: 0xFF111111,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    );

    expect(invalid.validate, throwsArgumentError);
  });
}
