import 'dart:typed_data';

/// Cheap ZIP central-directory preflight used before any archive decompression.
///
/// The guard intentionally reads only ZIP metadata from the compressed bytes.
/// This lets LexPDF reject oversized archives and classic ZIP bombs before the
/// archive package allocates memory for decompressed entries.
class LexBackupArchiveGuard {
  const LexBackupArchiveGuard._();

  static const int maxArchiveBytes = 8 * 1024 * 1024 * 1024;
  static const int maxEntries = 10050;
  static const int maxEntryUncompressedBytes = 2 * 1024 * 1024 * 1024;
  static const int maxTotalUncompressedBytes = 32 * 1024 * 1024 * 1024;
  static const int maxCompressionRatio = 250;

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
    if (entryCount > maxEntries) {
      throw const FormatException('Backup contains too many ZIP entries.');
    }
    if (centralOffset + centralSize > data.length) {
      throw const FormatException('Invalid ZIP central-directory bounds.');
    }

    var offset = centralOffset;
    var seen = 0;
    var totalUncompressed = 0;
    while (offset < centralOffset + centralSize) {
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
      if (uncompressed > 1024 * 1024) {
        if (compressed == 0 || uncompressed > compressed * maxCompressionRatio) {
          throw const FormatException('Backup entry has a suspicious compression ratio.');
        }
      }

      seen++;
      if (seen > maxEntries) {
        throw const FormatException('Backup contains too many ZIP entries.');
      }
      offset += 46 + nameLength + extraLength + commentLength;
    }

    if (seen != entryCount || offset != centralOffset + centralSize) {
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
