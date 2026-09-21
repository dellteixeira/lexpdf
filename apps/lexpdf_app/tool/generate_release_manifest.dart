import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  String? platform;
  String? version;
  String? output;
  final artifacts = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--platform':
        if (i + 1 >= args.length) return _usage();
        platform = args[++i];
        break;
      case '--version':
        if (i + 1 >= args.length) return _usage();
        version = args[++i];
        break;
      case '--output':
        if (i + 1 >= args.length) return _usage();
        output = args[++i];
        break;
      default:
        artifacts.add(args[i]);
        break;
    }
  }
  if (platform == null ||
      !const {'android', 'windows'}.contains(platform) ||
      version == null ||
      version.trim().isEmpty ||
      output == null ||
      artifacts.isEmpty) {
    return _usage();
  }
  final entries = <Map<String, Object?>>[];
  for (final path in artifacts) {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Release artifact not found.', path);
    }
    final stat = await file.stat();
    final digest = await sha256.bind(file.openRead()).first;
    entries.add({
      'file': file.uri.pathSegments.last,
      'bytes': stat.size,
      'sha256': digest.toString(),
    });
  }
  entries.sort((a, b) => (a['file'] as String).compareTo(b['file'] as String));
  final encoder = const JsonEncoder.withIndent('  ');
  await File(output).writeAsString('${encoder.convert({
    'schema': 'lexpdf-release-manifest-v1',
    'platform': platform,
    'version': version,
    'artifacts': entries,
  })}\n');
}

Never _usage() => throw ArgumentError(
      'Usage: --platform android|windows --version <version> '
      '--output <file> <artifact> [artifact...]',
    );
