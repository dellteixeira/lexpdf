import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// Random-access local PDF source used by the incremental searchable exporter.
///
/// The PDF parser requests only the ranges it needs instead of materializing
/// the complete source file in Dart heap. Access to the shared random-access
/// handle is serialized because its cursor is mutable.
class LocalPdfByteSource implements PdfByteSource {
  LocalPdfByteSource(this.path);

  final String path;
  RandomAccessFile? _file;
  int? _length;
  Future<void> _lock = Future<void>.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<RandomAccessFile> _open() async =>
      _file ??= await File(path).open(mode: FileMode.read);

  @override
  Future<int?> get length async => _length ??= await File(path).length();

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    final safeStart = math.max(0, start);
    if (endExclusive <= safeStart) return Uint8List(0);
    return _synchronized(() async {
      final file = await _open();
      final total = _length ??= await file.length();
      if (safeStart >= total) return Uint8List(0);
      final end = math.min(endExclusive, total);
      await file.setPosition(safeStart);
      return file.read(end - safeStart);
    });
  }

  @override
  Future<void> close() async {
    await _synchronized(() async {});
    final file = _file;
    _file = null;
    if (file != null) await file.close();
  }
}
