import 'dart:io';
import 'dart:typed_data';

/// ZIP central-directory preflight used before any archive decompression.
///
/// It rejects oversized archives, excessive entry counts, implausible
/// compression ratios and oversized expanded payloads before the archive
/// package is allowed to inflate any entry.
class LexBackupArchiveGuard {
  const LexBackupArchiveGuard._();

  static const int maxArchiveBytes = 8 * 1024 * 1024 * 1024;
  static const int maxCentralDirectoryBytes = 16 * 1024 * 1024;
  static const int maxEntries = 10050;
  static const int maxEntryUncompressedBytes = 2 * 1024 * 1024 * 1024;
  static const int maxTotalUncompressedBytes = 32 * 1024 * 1024 * 1024;
  static const int maxCompressionRatio = 250;

  /// Preflights a large backup without reading the whole archive into Dart heap.
  static Future<void> validateFile(File file) async {
    if (!await file.exists()) {
      throw const FormatException('Backup archive does not exist.');
    }
    final length = await file.length();
    if (length < 22) {
      throw const FormatException('Backup archive is truncated.');
    }
    if (length > maxArchiveBytes) {
      throw const FormatException('Backup archive exceeds the compressed-size safety limit.');
    }

    final handle = await file.open();
    try {
      final tailLength = length > 65557 ? 65557 : length;
      await handle.setPosition(length - tailLength);
      final tail = await handle.read(tailLength);
      final eocd = _findEndOfCentralDirectory(tail);
      if (eocd < 0) {
        throw const FormatException('Invalid ZIP end-of-central-directory record.');
      }

      final entryCount = _u16(tail, eocd + 10);
      final centralSize = _u32(tail, eocd + 12);
      final centralOffset = _u32(tail, eocd + 16);
      _validateDirectoryEnvelope(
        archiveLength: length,
        entryCount: entryCount,
        centralSize: centralSize,
        centralOffset: centralOffset,
      );

      await handle.setPosition(centralOffset);
      final central = await handle.read(centralSize);
      if (central.length != centralSize) {
        throw const FormatException('Truncated ZIP central directory.');
      }
      _validateCentralDirectory(
        Uint8List.fromList(central),
        expectedEntries: entryCount,
      );
    } finally {
      await handle.close();
    }
  }

  static void validateCompressedBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('Backup archive is empty.');
    }
    if (bytes.length > maxArchiveBytes) {
      throw const FormatException('Backup archive exceeds the compressed-size safety limit.');
    }

    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final eocd = _findEndOfCentralDirectory(data);
    if (eocd < 0) {
      throw const FormatException('Invalid ZIP end-of-central-directory record.');
    }

    final entryCount = _u16(data, eocd + 10);
    final centralSize = _u32(data, eocd + 12);
    final centralOffset = _u32(data, eocd + 16);
    _validateDirectoryEnvelope(
      archiveLength: data.length,
      entryCount: entryCount,
      centralSize: centralSize,
      centralOffset: centralOffset,
    );
    _validateCentralDirectory(
      Uint8List.sublistView(data, centralOffset, centralOffset + centralSize),
      expectedEntries: entryCount,
    );
  }

  static void _validateDirectoryEnvelope({
    required int archiveLength,
    required int entryCount,
    required int centralSize,
    required int centralOffset,
  }) {
    if (entryCount > maxEntries) {
      throw const FormatException('Backup contains too many ZIP entries.');
    }
    if (centralSize > maxCentralDirectoryBytes) {
      throw const FormatException('Backup ZIP central directory is unreasonably large.');
    }
    if (centralOffset < 0 || centralSize < 0 || centralOffset + centralSize > archiveLength) {
      throw const FormatException('Invalid ZIP central-directory bounds.');
    }
  }

  static void _validateCentralDirectory(
    Uint8List data, {
    required int expectedEntries,
  }) {
    var offset = 0;
    var seen = 0;
    var totalUncompressed = 0;
    while (offset < data.length) {
      if (offset + 46 > data.length || _u32(data, offset) != 0x02014b50) {
        throw const FormatException('Malformed ZIP central-directory entry.');
      }
      final compressed = _u32(data, offset + 20);
      final uncompressed = _u32(data, offset + 24);
      final nameLength = _u16(data, offset + 28);
      final extraLength = _u16(data, offset + 30);
      final commentLength = _u16(data, offset + 32);

      if (uncompressed > maxEntryUncompressedBytes) {
        throw const FormatException('Backup entry exceeds the uncompressed-size safety limit.');
      }
      totalUncompressed += uncompressed;
      if (totalUncompressed > maxTotalUncompressedBytes) {
        throw const FormatException('Backup exceeds the total uncompressed-size safety limit.');
      }
      if (uncompressed > 1024 * 1024 &&
          (compressed == 0 || uncompressed > compressed * maxCompressionRatio)) {
        throw const FormatException('Backup entry has a suspicious compression ratio.');
      }

      seen++;
      if (seen > maxEntries) {
        throw const FormatException('Backup contains too many ZIP entries.');
      }
      offset += 46 + nameLength + extraLength + commentLength;
    }

    if (seen != expectedEntries || offset != data.length) {
      throw const FormatException('ZIP central-directory entry count is inconsistent.');
    }
  }

  static int _findEndOfCentralDirectory(Uint8List data) {
    const minimumRecord = 22;
    if (data.length < minimumRecord) return -1;
    final lowerBound = data.length > 65557 ? data.length - 65557 : 0;
    for (var i = data.length - minimumRecord; i >= lowerBound; i--) {
      if (_u32(data, i) == 0x06054b50) return i;
    }
    return -1;
  }

  static int _u16(Uint8List data, int offset) {
    if (offset < 0 || offset + 2 > data.length) {
      throw const FormatException('Truncated ZIP metadata.');
    }
    return data[offset] | (data[offset + 1] << 8);
  }

  static int _u32(Uint8List data, int offset) {
    if (offset < 0 || offset + 4 > data.length) {
      throw const FormatException('Truncated ZIP metadata.');
    }
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }
}
