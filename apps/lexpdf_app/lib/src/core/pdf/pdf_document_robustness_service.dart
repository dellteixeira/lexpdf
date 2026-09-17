import 'dart:convert';
import 'dart:io';

/// Coarse document-health classification performed before the renderer opens a
/// local PDF. Inspection is deliberately bounded: it never reads the complete
/// document, even for multi-gigabyte files.
enum PdfRobustnessIssue {
  missing,
  inaccessible,
  emptyOrTruncated,
  invalidHeader,
}

class PdfDocumentRobustnessReport {
  const PdfDocumentRobustnessReport({
    required this.path,
    required this.lengthBytes,
    required this.hasPdfHeader,
    required this.hasEofMarker,
    required this.passwordProtected,
    required this.linearized,
    required this.readOnly,
    required this.longPath,
    required this.unicodePath,
    required this.hugeFile,
    this.blockingIssue,
    this.detail,
  });

  final String path;
  final int lengthBytes;
  final bool hasPdfHeader;
  final bool hasEofMarker;
  final bool passwordProtected;
  final bool linearized;
  final bool readOnly;
  final bool longPath;
  final bool unicodePath;
  final bool hugeFile;
  final PdfRobustnessIssue? blockingIssue;
  final String? detail;

  bool get canOpen => blockingIssue == null;

  bool get hasWarnings =>
      !hasEofMarker || passwordProtected || readOnly || longPath || hugeFile;

  String get blockingMessage => switch (blockingIssue) {
        PdfRobustnessIssue.missing =>
          'O arquivo PDF não foi encontrado. Ele pode ter sido movido, renomeado ou removido.',
        PdfRobustnessIssue.inaccessible =>
          detail ?? 'O LexPDF não conseguiu acessar este arquivo.',
        PdfRobustnessIssue.emptyOrTruncated =>
          'O arquivo está vazio ou incompleto e não pode ser aberto com segurança.',
        PdfRobustnessIssue.invalidHeader =>
          'O arquivo não contém um cabeçalho PDF válido.',
        null => '',
      };

  List<String> get warnings {
    final result = <String>[];
    if (!hasEofMarker) {
      result.add(
        'O marcador final do PDF não foi encontrado no trecho final do arquivo. O documento pode estar incompleto; a abertura será tentada pelo renderer.',
      );
    }
    if (passwordProtected) {
      result.add(
        'O PDF indica criptografia/proteção. Algumas operações podem exigir senha ou estar restritas pelo próprio documento.',
      );
    }
    if (readOnly) {
      result.add(
        'O arquivo está em modo somente leitura. O LexPDF preservará a leitura e deverá usar Salvar como para alterações no arquivo físico.',
      );
    }
    if (longPath) {
      result.add(
        'O caminho do arquivo é longo. O LexPDF manterá o caminho Unicode original sem copiar ou renomear o PDF.',
      );
    }
    if (hugeFile) {
      result.add(
        'PDF muito grande detectado. Renderização, overlays e OCR permanecerão limitados à janela/página ativa.',
      );
    }
    return result;
  }
}

class PdfDocumentRobustnessService {
  const PdfDocumentRobustnessService();

  static const int _headerProbeBytes = 4096;
  static const int _tailProbeBytes = 64 * 1024;
  static const int _minPdfBytes = 8;
  static const int hugeFileThresholdBytes = 512 * 1024 * 1024;

  Future<PdfDocumentRobustnessReport> inspect(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) {
        return _failure(
          path,
          PdfRobustnessIssue.missing,
          lengthBytes: 0,
        );
      }

      final length = await file.length();
      if (length < _minPdfBytes) {
        return _failure(
          path,
          PdfRobustnessIssue.emptyOrTruncated,
          lengthBytes: length,
        );
      }

      final handle = await file.open();
      try {
        final headLength = length < _headerProbeBytes
            ? length
            : _headerProbeBytes;
        final head = await handle.read(headLength);
        final hasHeader = _containsAscii(head, '%PDF-');
        if (!hasHeader) {
          return _failure(
            path,
            PdfRobustnessIssue.invalidHeader,
            lengthBytes: length,
          );
        }

        final tailLength = length < _tailProbeBytes ? length : _tailProbeBytes;
        await handle.setPosition(length - tailLength);
        final tail = await handle.read(tailLength);
        final combinedProbe = <int>[...head, ...tail];

        return PdfDocumentRobustnessReport(
          path: path,
          lengthBytes: length,
          hasPdfHeader: true,
          hasEofMarker: _containsAscii(tail, '%%EOF'),
          passwordProtected:
              _containsAscii(combinedProbe, '/Encrypt') ||
              _containsAscii(combinedProbe, '/Filter/Standard') ||
              _containsAscii(combinedProbe, '/Filter /Standard'),
          linearized:
              _containsAscii(head, '/Linearized') ||
              _containsAscii(head, '/Linearized '),
          readOnly: await _isReadOnly(file),
          longPath: _isLongPath(path),
          unicodePath: path.runes.any((value) => value > 0x7F),
          hugeFile: length >= hugeFileThresholdBytes,
        );
      } finally {
        await handle.close();
      }
    } on FileSystemException catch (error) {
      return _failure(
        path,
        PdfRobustnessIssue.inaccessible,
        lengthBytes: 0,
        detail: 'Não foi possível acessar o PDF: ${error.message}',
      );
    } catch (error) {
      return _failure(
        path,
        PdfRobustnessIssue.inaccessible,
        lengthBytes: 0,
        detail: 'Não foi possível validar o PDF: $error',
      );
    }
  }

  PdfDocumentRobustnessReport _failure(
    String path,
    PdfRobustnessIssue issue, {
    required int lengthBytes,
    String? detail,
  }) {
    return PdfDocumentRobustnessReport(
      path: path,
      lengthBytes: lengthBytes,
      hasPdfHeader: false,
      hasEofMarker: false,
      passwordProtected: false,
      linearized: false,
      readOnly: false,
      longPath: _isLongPath(path),
      unicodePath: path.runes.any((value) => value > 0x7F),
      hugeFile: lengthBytes >= hugeFileThresholdBytes,
      blockingIssue: issue,
      detail: detail,
    );
  }

  static bool _containsAscii(List<int> bytes, String needle) {
    if (bytes.isEmpty) return false;
    final haystack = latin1.decode(bytes, allowInvalid: true);
    return haystack.contains(needle);
  }

  static bool _isLongPath(String path) {
    // Windows long-path awareness is enabled natively; this flag is diagnostic
    // rather than a rejection rule. Keep a conservative cross-platform marker.
    return path.length >= 240;
  }

  static Future<bool> _isReadOnly(File file) async {
    // Do not probe writability by modifying/opening the source for write. On
    // POSIX the mode bits are available through stat. On Windows a source may
    // still be effectively read-only because of ACLs/cloud providers; write
    // operations remain protected by SafePdfWriter regardless of this hint.
    if (Platform.isWindows) return false;
    try {
      final mode = (await file.stat()).mode;
      return mode & 0x92 == 0; // no owner/group/other write bits (0222 octal)
    } catch (_) {
      return false;
    }
  }
}

/// Maps low-level renderer/storage failures to stable user-facing diagnostics.
enum PdfRuntimeFailureKind {
  passwordRequired,
  corruptOrUnsupported,
  outOfMemory,
  diskFull,
  permissionDenied,
  missingFile,
  unknown,
}

class PdfRuntimeFailure {
  const PdfRuntimeFailure(this.kind, this.message, {this.recoverable = true});

  final PdfRuntimeFailureKind kind;
  final String message;
  final bool recoverable;
}

class PdfRuntimeFailureClassifier {
  const PdfRuntimeFailureClassifier._();

  static PdfRuntimeFailure classify(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('password') || text.contains('encrypted')) {
      return const PdfRuntimeFailure(
        PdfRuntimeFailureKind.passwordRequired,
        'Este PDF é protegido. Informe a senha quando o mecanismo de PDF solicitar as credenciais.',
      );
    }
    if (text.contains('out of memory') ||
        text.contains('allocation failed') ||
        text.contains('bad_alloc')) {
      return const PdfRuntimeFailure(
        PdfRuntimeFailureKind.outOfMemory,
        'Memória insuficiente para concluir esta operação. Feche documentos não utilizados e tente novamente; o arquivo original foi preservado.',
      );
    }
    if (text.contains('no space left') ||
        text.contains('disk full') ||
        text.contains('enospc')) {
      return const PdfRuntimeFailure(
        PdfRuntimeFailureKind.diskFull,
        'Não há espaço livre suficiente para concluir a gravação. O LexPDF preservou o arquivo original.',
      );
    }
    if (text.contains('permission denied') || text.contains('access denied')) {
      return const PdfRuntimeFailure(
        PdfRuntimeFailureKind.permissionDenied,
        'O sistema bloqueou o acesso ao arquivo. Tente Salvar como em outro local ou verifique as permissões.',
      );
    }
    if (text.contains('not found') ||
        text.contains('cannot find') ||
        text.contains('no such file')) {
      return const PdfRuntimeFailure(
        PdfRuntimeFailureKind.missingFile,
        'O PDF não está mais no caminho original. Localize o arquivo novamente para continuar.',
      );
    }
    if (text.contains('corrupt') ||
        text.contains('invalid pdf') ||
        text.contains('malformed') ||
        text.contains('unsupported')) {
      return const PdfRuntimeFailure(
        PdfRuntimeFailureKind.corruptOrUnsupported,
        'O PDF parece corrompido ou usa um recurso não suportado. O arquivo original não foi alterado.',
      );
    }
    return PdfRuntimeFailure(
      PdfRuntimeFailureKind.unknown,
      'Não foi possível concluir a operação com este PDF. O arquivo original foi preservado.',
    );
  }
}
