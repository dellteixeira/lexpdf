import 'dart:io';

import 'pdf_document_robustness_service.dart';

class PdfFilePreflightResult {
  const PdfFilePreflightResult._({
    required this.canOpen,
    required this.lengthBytes,
    this.errorMessage,
    this.warningMessages = const [],
    this.passwordProtected = false,
    this.readOnly = false,
    this.hugeFile = false,
    this.unicodePath = false,
    this.longPath = false,
  });

  const PdfFilePreflightResult.ready({
    required int lengthBytes,
    List<String> warningMessages = const [],
    bool passwordProtected = false,
    bool readOnly = false,
    bool hugeFile = false,
    bool unicodePath = false,
    bool longPath = false,
  }) : this._(
          canOpen: true,
          lengthBytes: lengthBytes,
          warningMessages: warningMessages,
          passwordProtected: passwordProtected,
          readOnly: readOnly,
          hugeFile: hugeFile,
          unicodePath: unicodePath,
          longPath: longPath,
        );

  const PdfFilePreflightResult.failure({
    required String errorMessage,
    int lengthBytes = 0,
    List<String> warningMessages = const [],
  }) : this._(
          canOpen: false,
          lengthBytes: lengthBytes,
          errorMessage: errorMessage,
          warningMessages: warningMessages,
        );

  final bool canOpen;
  final int lengthBytes;
  final String? errorMessage;
  final List<String> warningMessages;
  final bool passwordProtected;
  final bool readOnly;
  final bool hugeFile;
  final bool unicodePath;
  final bool longPath;

  bool get hasWarnings => warningMessages.isNotEmpty;
}

class PdfFilePreflight {
  const PdfFilePreflight._();

  static const int _headerProbeBytes = 1024;
  static const List<int> _pdfSignature = [0x25, 0x50, 0x44, 0x46, 0x2D];

  /// Async Phase 8 preflight for production paths. It performs only bounded
  /// head/tail reads and is safe for giant PDFs, network-backed files and long
  /// Unicode paths. This is the preferred diagnostic entry point.
  static Future<PdfFilePreflightResult> inspect(
    String path, {
    PdfDocumentRobustnessService service = const PdfDocumentRobustnessService(),
  }) async {
    final report = await service.inspect(path);
    if (!report.canOpen) {
      return PdfFilePreflightResult.failure(
        errorMessage: report.blockingMessage,
        lengthBytes: report.lengthBytes,
        warningMessages: report.warnings,
      );
    }
    return PdfFilePreflightResult.ready(
      lengthBytes: report.lengthBytes,
      warningMessages: report.warnings,
      passwordProtected: report.passwordProtected,
      readOnly: report.readOnly,
      hugeFile: report.hugeFile,
      unicodePath: report.unicodePath,
      longPath: report.longPath,
    );
  }

  /// Performs the legacy bounded synchronous check used by existing reader
  /// contracts. Windows intentionally avoids synchronous filesystem I/O so a
  /// cloud/network path cannot freeze the UI isolate before the first frame.
  /// New robustness-sensitive paths should prefer [inspect].
  static PdfFilePreflightResult inspectSync(String path) {
    if (Platform.isWindows) {
      return const PdfFilePreflightResult.ready(lengthBytes: 0);
    }

    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const PdfFilePreflightResult.failure(
          errorMessage: 'O arquivo PDF local não foi encontrado.',
        );
      }

      final length = file.lengthSync();
      if (length < _pdfSignature.length) {
        return PdfFilePreflightResult.failure(
          errorMessage: 'O arquivo PDF está vazio ou incompleto.',
          lengthBytes: length,
        );
      }

      final handle = file.openSync();
      try {
        final probeLength = length < _headerProbeBytes
            ? length
            : _headerProbeBytes;
        final prefix = handle.readSync(probeLength);
        if (!_containsPdfSignature(prefix)) {
          return PdfFilePreflightResult.failure(
            errorMessage: 'O arquivo local não contém um cabeçalho PDF válido.',
            lengthBytes: length,
          );
        }
      } finally {
        handle.closeSync();
      }

      return PdfFilePreflightResult.ready(lengthBytes: length);
    } on FileSystemException catch (error) {
      return PdfFilePreflightResult.failure(
        errorMessage: 'Não foi possível acessar o arquivo PDF local: ${error.message}',
      );
    } catch (error) {
      return PdfFilePreflightResult.failure(
        errorMessage: 'Não foi possível validar o arquivo PDF local: $error',
      );
    }
  }

  static bool _containsPdfSignature(List<int> bytes) {
    if (bytes.length < _pdfSignature.length) return false;
    final limit = bytes.length - _pdfSignature.length;
    for (var offset = 0; offset <= limit; offset++) {
      var matches = true;
      for (var index = 0; index < _pdfSignature.length; index++) {
        if (bytes[offset + index] != _pdfSignature[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }
}
