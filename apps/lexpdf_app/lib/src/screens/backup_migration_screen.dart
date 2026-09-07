import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/backup/lex_backup_service.dart';
import '../core/backup/lex_backup_streaming_restore_service.dart';
import '../core/backup/lex_backup_streaming_service.dart';
import '../core/backup/squid_import_service.dart';
import '../core/storage/local_database.dart';

class BackupMigrationScreen extends StatefulWidget {
  const BackupMigrationScreen({required this.db, super.key});

  final LocalDatabase db;

  @override
  State<BackupMigrationScreen> createState() => _BackupMigrationScreenState();
}

class _BackupMigrationScreenState extends State<BackupMigrationScreen> {
  late final LexBackupService _backup = LexBackupService(widget.db);
  late final LexBackupStreamingService _streamingBackup =
      LexBackupStreamingService(widget.db);
  late final LexBackupStreamingRestoreService _streamingRestore =
      LexBackupStreamingRestoreService(widget.db);
  static const SquidImportService _squid = SquidImportService();
  bool _busy = false;

  Future<String?> _saveBytes(Uint8List bytes, String suggestedName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(suggestedName: suggestedName);
      if (location == null) return null;
      await XFile.fromData(bytes, name: suggestedName).saveTo(location.path);
      return location.path;
    }
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${directory.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}backups',
    );
    await folder.create(recursive: true);
    final path = '${folder.path}${Platform.pathSeparator}$suggestedName';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<String?> _backupDestination(String suggestedName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(suggestedName: suggestedName);
      return location?.path;
    }
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${directory.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}backups',
    );
    await folder.create(recursive: true);
    return '${folder.path}${Platform.pathSeparator}$suggestedName';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operação não concluída: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBackup() => _run(() async {
        final name =
            'lexpdf_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.lexbackup';
        final path = await _backupDestination(name);
        if (path == null) return;
        final file = await _streamingBackup.createBackupFile(path);
        final validation = await _streamingRestore.validateFile(file);
        if (!validation.valid) {
          if (await file.exists()) await file.delete();
          throw StateError(
            validation.error ?? 'O backup criado não passou na validação.',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup validado e salvo em: ${file.path}')),
          );
        }
      });

  Future<void> _restoreBackup() => _run(() async {
        const type = XTypeGroup(label: 'LexPDF backup', extensions: ['lexbackup']);
        final selected = await openFile(acceptedTypeGroups: const [type]);
        if (selected == null) return;
        final source = File(selected.path);
        final validation = await _streamingRestore.validateFile(source);
        if (!validation.valid) {
          throw FormatException(validation.error ?? 'Backup inválido.');
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restaurar backup?'),
            content: Text(
              'Backup válido: ${validation.tableCount} tabelas e ${validation.fileCount} documentos. A restauração substituirá o estado local atual.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restaurar'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final documents = await getApplicationDocumentsDirectory();
        final target = Directory(
          '${documents.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}restored-documents',
        );
        await _streamingRestore.restoreFile(source, documentDirectory: target);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup restaurado e validado.')),
          );
        }
      });

  Future<void> _exportLexNote() => _run(() async {
        final rows = widget.db.database.select(
          'SELECT id, title FROM notebooks ORDER BY updated_at DESC;',
        );
        if (rows.isEmpty) throw StateError('Nenhum caderno disponível.');
        if (!mounted) return;
        final notebookId = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Exportar .lexnote'),
            children: [
              for (final row in rows)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, row['id'] as String),
                  child: Text(row['title'] as String),
                ),
            ],
          ),
        );
        if (notebookId == null) return;
        final bytes = _backup.exportNotebook(notebookId);
        final validation = _backup.validateNotebook(bytes);
        if (!validation.valid) {
          throw StateError(
            validation.error ?? 'O .lexnote criado não passou na validação.',
          );
        }
        final safeTitle = (validation.title ?? 'caderno').replaceAll(
          RegExp(r'[^A-Za-z0-9._-]+'),
          '_',
        );
        final path = await _saveBytes(bytes, '$safeTitle.lexnote');
        if (mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('.lexnote validado e salvo em: $path')),
          );
        }
      });

  Future<void> _importLexNote() => _run(() async {
        const type = XTypeGroup(label: 'LexPDF notebook', extensions: ['lexnote']);
        final file = await openFile(acceptedTypeGroups: const [type]);
        if (file == null) return;
        final bytes = await file.readAsBytes();
        final validation = _backup.validateNotebook(bytes);
        if (!validation.valid) {
          throw FormatException(validation.error ?? '.lexnote inválido.');
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Importar caderno?'),
            content: Text(
              '${validation.title ?? 'Caderno'}: ${validation.pageCount} página(s), '
              '${validation.strokeCount} traço(s), ${validation.objectCount} objeto(s) e '
              '${validation.layerCount} camada(s). O original será preservado e uma nova cópia será criada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Importar'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final result = _backup.importNotebook(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${result.title} importado: ${result.pageCount} página(s), '
                '${result.strokeCount} traço(s) e ${result.objectCount} objeto(s).',
              ),
            ),
          );
        }
      });

  Future<void> _importSquid() => _run(() async {
        const type = XTypeGroup(
          label: 'Squid/PDF',
          extensions: ['squid', 'zip', 'pdf'],
        );
        final file = await openFile(acceptedTypeGroups: const [type]);
        if (file == null) return;
        final documents = await getApplicationDocumentsDirectory();
        final destination = Directory(
          '${documents.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}imports',
        );
        final result = await _squid.importSafely(
          file.path,
          destination: destination,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${result.importedFiles.length} arquivo(s) importado(s). ${result.warnings.join(' ')}',
              ),
            ),
          );
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup e migração')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Proteção dos dados',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Backups e cadernos portáteis são validados por checksum antes de restauração/importação. O estado local continua sendo a fonte primária offline.',
          ),
          const SizedBox(height: 24),
          _ActionTile(
            icon: Icons.backup_outlined,
            title: 'Criar .lexbackup',
            subtitle: 'Banco local + documentos disponíveis offline',
            onTap: _busy ? null : _createBackup,
          ),
          _ActionTile(
            icon: Icons.restore_outlined,
            title: 'Validar e restaurar .lexbackup',
            subtitle: 'Restauração transacional com verificação de integridade',
            onTap: _busy ? null : _restoreBackup,
          ),
          _ActionTile(
            icon: Icons.note_outlined,
            title: 'Exportar caderno .lexnote',
            subtitle: 'Formato editável portátil do LexPDF, incluindo camadas',
            onTap: _busy ? null : _exportLexNote,
          ),
          _ActionTile(
            icon: Icons.note_add_outlined,
            title: 'Validar e importar .lexnote',
            subtitle: 'Cria uma nova cópia sem sobrescrever o caderno original',
            onTap: _busy ? null : _importLexNote,
          ),
          _ActionTile(
            icon: Icons.system_update_alt,
            title: 'Importar Squid com fallback seguro',
            subtitle: 'Importa PDFs reconhecíveis sem inventar camadas proprietárias',
            onTap: _busy ? null : _importSquid,
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
