import 'dart:io';

class PdfFilePreflightResult {
  const PdfFilePreflightResult._({
    required this.canOpen,
    required this.lengthBytes,
    this.errorMessage,
  });

  const PdfFilePreflightResult.ready({required int lengthBytes})
      : this._(canOpen: true, lengthBytes: lengthBytes);

  const PdfFilePreflightResult.failure({
    required String errorMessage,
    int lengthBytes = 0,
  }) : this._(
          canOpen: false,
          lengthBytes: lengthBytes,
          errorMessage: errorMessage,
        );

  final bool canOpen;
  final int lengthBytes;
  final String? errorMessage;
}

class PdfFilePreflight {
  const PdfFilePreflight._();

  static const int _headerProbeBytes = 1024;
  static const List<int> _pdfSignature = [0x25, 0x50, 0x44, 0x46, 0x2D];

  /// Performs a bounded local-file check before PDFium receives the path.
  ///
  /// Only metadata and at most the first 1 KiB are read, so the cost does not
  /// grow with the number of pages or the total PDF size.
  static PdfFilePreflightResult inspectSync(String path) {
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
