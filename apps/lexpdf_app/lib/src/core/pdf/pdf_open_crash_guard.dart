import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

typedef PdfCrashGuardDirectoryProvider = Future<Directory> Function();

class PdfOpenCrashGuardState {
  const PdfOpenCrashGuardState({
    required this.recoveryLevel,
    required this.hadInterruptedOpen,
  });

  static const normal = PdfOpenCrashGuardState(
    recoveryLevel: 0,
    hadInterruptedOpen: false,
  );

  final int recoveryLevel;
  final bool hadInterruptedOpen;

  bool get recoveryMode => recoveryLevel > 0;
}

/// Tiny persistent guard around the native PDF opening window.
///
/// Android can terminate the process from native/PDFium code or memory pressure
/// without giving Dart an exception to catch. The marker is written *before*
/// the viewer is mounted and cleared only after a stable viewing window. If the
/// next process sees the same unfinished marker it automatically escalates that
/// document to a lower-memory recovery profile.
///
/// The marker stores only a SHA-256 document key, never the local file path.
class PdfOpenCrashGuard {
  const PdfOpenCrashGuard({this.directoryProvider});

  static const Duration interruptedOpenWindow = Duration(minutes: 30);
  static const String _markerName = 'pdf-open-in-progress.json';

  final PdfCrashGuardDirectoryProvider? directoryProvider;

  Future<PdfOpenCrashGuardState> begin(String documentId) async {
    final file = await _markerFile();
    final now = DateTime.now().toUtc();
    final key = _documentKey(documentId);

    var recoveryLevel = 0;
    var interrupted = false;

    final previous = await _readMarker(file);
    if (previous != null && previous.documentKey == key) {
      final age = now.difference(previous.startedAt);
      if (!age.isNegative && age <= interruptedOpenWindow) {
        interrupted = true;
        recoveryLevel = (previous.recoveryLevel + 1).clamp(1, 2).toInt();
      }
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object>{
        'documentKey': key,
        'startedAt': now.toIso8601String(),
        'recoveryLevel': recoveryLevel,
      }),
      flush: true,
    );

    return PdfOpenCrashGuardState(
      recoveryLevel: recoveryLevel,
      hadInterruptedOpen: interrupted,
    );
  }

  Future<void> markStable(String documentId) async {
    final file = await _markerFile();
    final marker = await _readMarker(file);
    if (marker == null || marker.documentKey != _documentKey(documentId)) {
      return;
    }
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Recovery metadata must never make PDF reading fail.
    }
  }

  Future<File> _markerFile() async {
    final directory = directoryProvider == null
        ? await getApplicationSupportDirectory()
        : await directoryProvider!();
    return File(
      '${directory.path}${Platform.pathSeparator}$_markerName',
    );
  }

  Future<_PdfOpenMarker?> _readMarker(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final key = decoded['documentKey'];
      final startedAt = decoded['startedAt'];
      final level = decoded['recoveryLevel'];
      if (key is! String || startedAt is! String || level is! int) return null;

      final parsed = DateTime.tryParse(startedAt);
      if (parsed == null) return null;
      return _PdfOpenMarker(
        documentKey: key,
        startedAt: parsed.toUtc(),
        recoveryLevel: level.clamp(0, 2).toInt(),
      );
    } on Object {
      return null;
    }
  }

  String _documentKey(String documentId) =>
      sha256.convert(utf8.encode(documentId)).toString();
}

class _PdfOpenMarker {
  const _PdfOpenMarker({
    required this.documentKey,
    required this.startedAt,
    required this.recoveryLevel,
  });

  final String documentKey;
  final DateTime startedAt;
  final int recoveryLevel;
}
