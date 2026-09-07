import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/backup/squid_import_service.dart';

void main() {
  test('imports embedded PDFs without overwriting duplicate names', () async {
    final temp = await Directory.systemTemp.createTemp('lexpdf-squid-test-');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}sample.squid');
    final destination = Directory('${temp.path}${Platform.pathSeparator}imports');

    final archive = Archive()
      ..addFile(ArchiveFile.bytes('one/document.pdf', const [1, 2, 3]))
      ..addFile(ArchiveFile.bytes('two/document.pdf', const [4, 5, 6]));
    await source.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);

    const service = SquidImportService();
    final result = await service.importSafely(source.path, destination: destination);

    expect(result.importedFiles, hasLength(2));
    expect(result.importedFiles.toSet(), hasLength(2));
    expect(await File(result.importedFiles[0]).readAsBytes(), const [1, 2, 3]);
    expect(await File(result.importedFiles[1]).readAsBytes(), const [4, 5, 6]);
    expect(await source.exists(), isTrue);
  });

  test('leaves unsupported Squid source unchanged', () async {
    final temp = await Directory.systemTemp.createTemp('lexpdf-squid-invalid-');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}unsupported.squid');
    final destination = Directory('${temp.path}${Platform.pathSeparator}imports');
    await source.writeAsBytes(const [1, 2, 3, 4], flush: true);

    const service = SquidImportService();
    await expectLater(
      service.importSafely(source.path, destination: destination),
      throwsA(isA<FormatException>()),
    );

    expect(await source.readAsBytes(), const [1, 2, 3, 4]);
    expect(await destination.list().toList(), isEmpty);
  });
}
