import 'dart:io';
import 'package:flutter/services.dart';

class LegacyWordConverter {
  const LegacyWordConverter();

  static const MethodChannel _channel = MethodChannel(
    'lexpdf/legacy_word_converter',
  );

  Future<bool> isAvailable() async {
    if (await _channelAvailable()) return true;
    if (!Platform.isWindows) return false;
    return await _findSoffice() != null || await _wordComAvailable();
  }

  Future<Uint8List?> toDocx(
    Uint8List sourceBytes, {
    required String sourceExtension,
  }) async {
    final channel = await _invokeBytes('toDocx', {
      'bytes': sourceBytes,
      'sourceExtension': sourceExtension.toLowerCase(),
    });
    if (channel != null) return channel;
    if (!Platform.isWindows) return null;
    return _convertOnWindows(
      sourceBytes,
      sourceExtension: sourceExtension.toLowerCase(),
      targetExtension: 'docx',
    );
  }

  Future<Uint8List?> fromDocx(
    Uint8List docxBytes, {
    required String targetExtension,
  }) async {
    final channel = await _invokeBytes('fromDocx', {
      'bytes': docxBytes,
      'targetExtension': targetExtension.toLowerCase(),
    });
    if (channel != null) return channel;
    if (!Platform.isWindows) return null;
    return _convertOnWindows(
      docxBytes,
      sourceExtension: 'docx',
      targetExtension: targetExtension.toLowerCase(),
    );
  }

  Future<bool> _channelAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Uint8List?> _invokeBytes(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      if (!await _channelAvailable()) return null;
      return await _channel.invokeMethod<Uint8List>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Uint8List?> _convertOnWindows(
    Uint8List bytes, {
    required String sourceExtension,
    required String targetExtension,
  }) async {
    if (targetExtension != 'docx' && targetExtension != 'doc') return null;
    final directory =
        await Directory.systemTemp.createTemp('lexpdf-word-convert-');
    try {
      final input = File(
        '${directory.path}${Platform.pathSeparator}input.$sourceExtension',
      );
      await input.writeAsBytes(bytes, flush: true);
      final output = File(
        '${directory.path}${Platform.pathSeparator}input.$targetExtension',
      );

      final soffice = await _findSoffice();
      if (soffice != null) {
        final filter = targetExtension == 'doc'
            ? 'doc:MS Word 97'
            : 'docx:Office Open XML Text';
        final result = await Process.run(
          soffice,
          [
            '--headless',
            '--convert-to',
            filter,
            '--outdir',
            directory.path,
            input.path,
          ],
          runInShell: false,
        );
        if (result.exitCode == 0 && await output.exists()) {
          return await output.readAsBytes();
        }
      }

      if (await _convertWithWordCom(
        input: input,
        output: output,
        targetExtension: targetExtension,
      )) {
        return await output.readAsBytes();
      }
      return null;
    } finally {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<String?> _findSoffice() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'where.exe',
        const ['soffice.exe'],
        runInShell: false,
      );
      if (result.exitCode == 0) {
        final first = result.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && await File(first).exists()) return first;
      }
    } catch (_) {}

    final programFiles = <String?>[
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
    ];
    for (final root in programFiles.whereType<String>()) {
      final candidate =
          '$root${Platform.pathSeparator}LibreOffice${Platform.pathSeparator}'
          'program${Platform.pathSeparator}soffice.exe';
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<bool> _wordComAvailable() async {
    if (!Platform.isWindows) return false;
    const script = r'''
      $ErrorActionPreference = 'Stop'
      $word = $null
      try {
        $word = New-Object -ComObject Word.Application
        Write-Output 'LEXPDF_WORD_OK'
      } catch {
        exit 2
      } finally {
        if ($word -ne $null) { $word.Quit() }
      }
    ''';
    try {
      final result = await Process.run(
        'powershell.exe',
        const ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );
      return result.exitCode == 0 &&
          result.stdout.toString().contains('LEXPDF_WORD_OK');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _convertWithWordCom({
    required File input,
    required File output,
    required String targetExtension,
  }) async {
    final format = targetExtension == 'docx' ? 16 : 0;
    final source = _psQuote(input.absolute.path);
    final target = _psQuote(output.absolute.path);
    final script = [
      r"$ErrorActionPreference = 'Stop'",
      r'$word = $null',
      r'$doc = $null',
      'try {',
      r'  $word = New-Object -ComObject Word.Application',
      r'  $word.Visible = $false',
      r'  $word.DisplayAlerts = 0',
      "  \$doc = \$word.Documents.Open('$source', \$false, \$true)",
      "  \$doc.SaveAs2('$target', $format)",
      r'  $doc.Close($false)',
      r'  $doc = $null',
      r'  $word.Quit()',
      r'  $word = $null',
      "  Write-Output 'LEXPDF_CONVERT_OK'",
      '} catch {',
      r'  if ($doc -ne $null) { $doc.Close($false) }',
      r'  if ($word -ne $null) { $word.Quit() }',
      '  exit 3',
      '}',
    ].join('\n');
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );
      return result.exitCode == 0 &&
          result.stdout.toString().contains('LEXPDF_CONVERT_OK') &&
          await output.exists() &&
          await output.length() > 0;
    } catch (_) {
      return false;
    }
  }

  static String _psQuote(String value) => value.replaceAll("'", "''");
}
