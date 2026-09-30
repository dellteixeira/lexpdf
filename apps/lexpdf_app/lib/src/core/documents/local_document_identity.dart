import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'document_provider.dart';

/// Stable local-document identity that does not depend on a filesystem path.
///
/// The fingerprint samples the beginning, middle and end of the file plus its
/// length. It bounds I/O to ~192 KB even for multi-gigabyte PDFs while making a
/// rename/move produce the same identity. It is an identity fingerprint, not a
/// cryptographic checksum of every byte in the document.
class LocalDocumentIdentity {
  const LocalDocumentIdentity();

  static const int sampleBytes = 64 * 1024;
  static const String idPrefix = 'local:v1:';

  Future<String> fingerprintFile(String path) async {
    final file = File(path);
    final length = await file.length();
    final handle = await file.open();
    try {
      final builder = BytesBuilder(copy: false)
        ..add(utf8.encode('LexPDF-local-identity-v1|$length|'));

      Future<void> sampleAt(int offset) async {
        await handle.setPosition(offset);
        builder.add(await handle.read(math.min(sampleBytes, length - offset)));
      }

      if (length > 0) {
        await sampleAt(0);
        if (length > sampleBytes * 2) {
          final middle = math.max(
            0,
            (length ~/ 2) - (sampleBytes ~/ 2),
          );
          await sampleAt(middle);
        }
        if (length > sampleBytes) {
          await sampleAt(math.max(0, length - sampleBytes));
        }
      }

      return sha256.convert(builder.takeBytes()).toString();
    } finally {
      await handle.close();
    }
  }

  Future<DocumentRef> identifyLocal({
    required String path,
    required String name,
  }) async {
    final fingerprint = await fingerprintFile(path);
    return DocumentRef(
      id: '$idPrefix$fingerprint',
      name: name,
      provider: DocumentProviderKind.local,
      localPath: path,
      availableOffline: true,
      syncState: DocumentSyncState.localOnly,
    );
  }

  String? fingerprintFromId(String id) =>
      id.startsWith(idPrefix) ? id.substring(idPrefix.length) : null;
}
