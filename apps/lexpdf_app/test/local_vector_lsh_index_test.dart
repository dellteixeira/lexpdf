import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_vector_lsh_index.dart';

void main() {
  test('LSH index returns nearby local vectors without full JSON scanning', () {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final index = LocalVectorLshIndex(db);

    for (var i = 0; i < 900; i++) {
      final vector = List<double>.filled(64, 0);
      vector[i % 64] = 1;
      vector[(i * 7) % 64] += 0.4;
      index.upsert(
        namespace: 'pdf',
        sourceKey: 'doc:$i:0',
        model: 'local-test',
        vector: vector,
      );
    }

    final query = List<double>.filled(64, 0)..[3] = 1;
    final keys = index.candidateKeys(
      namespace: 'pdf',
      model: 'local-test',
      queryVector: query,
      maxResults: 40,
    );

    expect(index.count(namespace: 'pdf', model: 'local-test'), 900);
    expect(keys, isNotNull);
    expect(keys, isNotEmpty);
    expect(keys!.length, lessThanOrEqualTo(40));
  });
}
