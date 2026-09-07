import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/backend/backend_config.dart';
import '../core/cloud/cloud_credential_store.dart';
import '../core/cloud/cloud_oauth_service.dart';
import '../core/cloud/native_file_provider_service.dart';
import '../core/storage/local_cloud_account_store.dart';
import '../core/storage/local_cloud_cache_store.dart';
import '../core/storage/local_database.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_sync_store.dart';
import '../core/sync/cloud_sync_coordinator.dart';
import '../core/sync/cloud_sync_provider_factory.dart';
import 'cloud_files_screen.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({required this.db, super.key});

  final LocalDatabase db;

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  late final LocalCloudAccountStore _accounts;
  late final LocalCloudCacheStore _cache;
  late final LocalDocumentCatalog _catalog;
  late final LocalSyncStore _sync;
  final CloudCredentialStore _credentials = const CloudCredentialStore();
  final CloudOAuthService _oauth = CloudOAuthService();
  static const NativeFileProviderService _fileProvider = NativeFileProviderService();

  late Future<void> _loadFuture;
  List<LocalCloudAccount> _accountItems = const [];
  List<LocalSyncItem> _queue = const [];
  List<LocalSyncConflict> _conflicts = const [];
  List<CloudCacheEntry> _cacheItems = const [];
  bool _connecting = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _accounts = LocalCloudAccountStore(widget.db);
    _cache = LocalCloudCacheStore(widget.db);
    _catalog = LocalDocumentCatalog(widget.db);
    _sync = LocalSyncStore(widget.db);
    _loadFuture = _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _sync.recoverInterrupted();
    await _load();
  }

  Future<void> _load() async {
    await _cache.pruneMissingFiles();
    final accounts = await _accounts.list();
    final queue = await _sync.list();
    final conflicts = await _sync.listConflicts(unresolvedOnly: true);
    final cacheItems = await _cache.list();
    if (!mounted) return;
    setState(() {
      _accountItems = accounts;
      _queue = queue;
      _conflicts = conflicts;
      _cacheItems = cacheItems;
    });
  }

  Future<CloudSyncCoordinator> _coordinator() async {
    final root = await getApplicationSupportDirectory();
    final factory = CloudSyncProviderFactory(
      accounts: _accounts,
      cacheRoot: Directory(
        '${root.path}${Platform.pathSeparator}cloud-cache',
      ),
    );
    return CloudSyncCoordinator(
      catalog: _catalog,
      store: _sync,
      resolveProvider: factory.resolve,
    );
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    var scanned = 0;
    var completed = 0;
    var failures = 0;
    try {
      final coordinator = await _coordinator();
      final bindings = await _sync.listBindings();
      for (final binding in bindings) {
        try {
          await coordinator.scanAndQueue(
            documentId: binding.entityId,
            provider: binding.provider,
            accountId: binding.accountId,
          );
          scanned++;
        } catch (_) {
          failures++;
        }
      }

      final engine = coordinator.engine();
      for (var round = 0; round < 4; round++) {
        final count = await engine.drain(limit: 25);
        completed += count;
        if (count == 0) break;
      }
      await _load();
      _message(
        'Sync concluído: $scanned verificados, $completed operações executadas'
        '${failures == 0 ? '' : ', $failures verificações com erro'}.',
      );
    } catch (error) {
      _message('Sincronização não concluída: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<String?> _askAlias(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Identificador local da conta',
            hintText: 'Ex.: pessoal, trabalho',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _connectGoogle() async {
    final alias = await _askAlias('Conectar Google Drive');
    if (alias == null) return;
    await _connect(() async {
      await _oauth.connectGoogleDrive(accountId: alias);
      await _accounts.upsert(
        LocalCloudAccount(
          provider: 'google_drive',
          accountId: alias,
          displayName: 'Google Drive • $alias',
          gatewayUrl: '',
          status: 'connected',
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    });
  }

  Future<void> _connectOneDrive() async {
    final alias = await _askAlias('Conectar OneDrive');
    if (alias == null) return;
    await _connect(() async {
      await _oauth.connectOneDrive(accountId: alias);
      await _accounts.upsert(
        LocalCloudAccount(
          provider: 'onedrive',
          accountId: alias,
          displayName: 'OneDrive • $alias',
          gatewayUrl: '',
          status: 'connected',
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    });
  }

  Future<void> _connectR2() async {
    final account = TextEditingController(text: 'default');
    final gateway = TextEditingController(
      text: BackendConfig.fromEnvironment.cloudGatewayUrl,
    );
    final token = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar LexPDF Cloud / R2'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: account,
                decoration: const InputDecoration(labelText: 'Conta'),
              ),
              TextField(
                controller: gateway,
                decoration: const InputDecoration(labelText: 'Gateway HTTPS'),
              ),
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token Supabase/gateway',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      final accountId = account.text.trim();
      final gatewayUrl = gateway.text.trim();
      final secret = token.text;
      final uri = Uri.tryParse(gatewayUrl);
      if (accountId.isEmpty ||
          secret.isEmpty ||
          uri == null ||
          uri.scheme != 'https') {
        _message('Conta, token e gateway HTTPS válido são obrigatórios.');
      } else {
        await _connect(() async {
          await _credentials.writeToken(
            provider: 'r2',
            accountId: accountId,
            token: secret,
          );
          await _accounts.upsert(
            LocalCloudAccount(
              provider: 'r2',
              accountId: accountId,
              displayName: 'LexPDF Cloud • $accountId',
              gatewayUrl: gatewayUrl,
              status: 'connected',
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        });
      }
    }
    account.dispose();
    gateway.dispose();
    token.dispose();
  }

  Future<void> _importFileProvider() async {
    await _connect(() async {
      final root = await getApplicationSupportDirectory();
      final cacheDirectory = Directory(
        '${root.path}${Platform.pathSeparator}cloud-cache${Platform.pathSeparator}icloud',
      );
      final document = await _fileProvider.pickPdf(
        cacheDirectory: cacheDirectory,
      );
      if (document == null) return;
      await _catalog.upsert(document);
      await _cache.upsert(
        documentId: document.id,
        provider: 'icloud',
        accountId: 'file-provider',
        localPath: document.localPath!,
        pinned: true,
      );
      _message('${document.name} disponível offline pelo File Provider.');
    });
  }

  Future<void> _connect(Future<void> Function() action) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await action();
      await _load();
    } catch (error) {
      _message('Não foi possível concluir: $error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _remove(LocalCloudAccount account) async {
    await _credentials.deleteToken(
      provider: account.provider,
      accountId: account.accountId,
    );
    await _accounts.remove(account.provider, account.accountId);
    await _load();
  }

  Future<String?> _accountForConflict(LocalSyncConflict conflict) async {
    final binding = await _sync.bindingFor(conflict.entityId);
    if (binding != null) return binding.accountId;
    final matches = _accountItems
        .where((account) => account.provider == conflict.provider)
        .toList(growable: false);
    if (matches.length == 1) {
      await _sync.bindAccount(
        entityId: conflict.entityId,
        provider: conflict.provider,
        accountId: matches.single.accountId,
      );
      return matches.single.accountId;
    }
    if (matches.isEmpty || !mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Escolha a conta para resolver o conflito'),
        children: [
          for (final account in matches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, account.accountId),
              child: Text(account.displayName),
            ),
        ],
      ),
    );
  }

  Future<void> _resolve(
    LocalSyncConflict conflict,
    ConflictResolution resolution,
  ) async {
    final accountId = await _accountForConflict(conflict);
    if (accountId == null) {
      _message('Não foi possível determinar a conta deste conflito.');
      return;
    }
    try {
      final coordinator = await _coordinator();
      await coordinator.resolveConflict(
        conflict: conflict,
        resolution: resolution,
        accountId: accountId,
      );
      await _load();
      _message('Conflito resolvido: ${_resolutionLabel(resolution)}.');
    } catch (error) {
      _message('Não foi possível resolver o conflito: $error');
    }
  }

  String _resolutionLabel(ConflictResolution value) => switch (value) {
        ConflictResolution.keepLocal => 'versão local mantida',
        ConflictResolution.keepRemote => 'versão remota mantida',
        ConflictResolution.keepBoth => 'ambas as versões preservadas',
      };

  Future<void> _setPinned(CloudCacheEntry entry, bool value) async {
    await _cache.setPinned(
      entry.documentId,
      entry.provider,
      entry.accountId,
      value,
    );
    await _load();
  }

  Future<void> _trimCache() async {
    const maxBytes = 1024 * 1024 * 1024;
    final removed = await _cache.evictToLimit(maxBytes);
    await _load();
    _message('$removed item(ns) removido(s) do cache não fixado.');
  }

  @override
  Widget build(BuildContext context) {
    final pending = _queue
        .where((item) =>
            item.status == LocalSyncStatus.pending ||
            item.status == LocalSyncStatus.retry)
        .length;
    final failed = _queue
        .where((item) => item.status == LocalSyncStatus.failed)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuvem e sincronização'),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_syncing ? 'Sincronizando…' : 'Sincronizar agora'),
          ),
          IconButton(
            onPressed: _connecting || _syncing ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text('$pending pendente(s)'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.compare_arrows, size: 18),
                    label: Text('${_conflicts.length} conflito(s)'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.error_outline, size: 18),
                    label: Text('$failed falha(s)'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Provedores', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _connecting || !_oauth.googleConfigured
                        ? null
                        : _connectGoogle,
                    icon: const Icon(Icons.add_to_drive_outlined),
                    label: Text(
                      _oauth.googleConfigured
                          ? 'Google Drive'
                          : 'Google Drive • configure Client ID',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _connecting || !_oauth.microsoftConfigured
                        ? null
                        : _connectOneDrive,
                    icon: const Icon(Icons.cloud_outlined),
                    label: Text(
                      _oauth.microsoftConfigured
                          ? 'OneDrive'
                          : 'OneDrive • configure Client ID',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _connecting ? null : _importFileProvider,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('iCloud / File Provider'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _connecting ? null : _connectR2,
                    icon: const Icon(Icons.cloud_queue_outlined),
                    label: const Text('LexPDF Cloud / R2'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Contas conectadas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_accountItems.isEmpty)
                const Card(
                  child: ListTile(title: Text('Nenhuma conta conectada.')),
                )
              else
                for (final account in _accountItems)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: Text(account.displayName),
                      subtitle: Text('${account.provider} • ${account.status}'),
                      onTap: account.provider == 'icloud'
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CloudFilesScreen(
                                    account: account,
                                    catalog: _catalog,
                                    syncStore: _sync,
                                  ),
                                ),
                              ),
                      trailing: IconButton(
                        tooltip: 'Desconectar',
                        onPressed: () => _remove(account),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Disponibilidade offline',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _trimCache,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Limitar a 1 GB'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_cacheItems.isEmpty)
                const Card(
                  child: ListTile(title: Text('Nenhum arquivo cloud em cache.')),
                )
              else
                for (final entry in _cacheItems)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.offline_pin_outlined),
                      title: Text(entry.documentId),
                      subtitle: Text(
                        '${entry.provider} • ${(entry.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                      ),
                      trailing: IconButton(
                        tooltip: entry.pinned
                            ? 'Permitir remoção automática'
                            : 'Manter sempre offline',
                        onPressed: () => _setPinned(entry, !entry.pinned),
                        icon: Icon(
                          entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
              Text(
                'Fila de sincronização',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_queue.isEmpty)
                const Card(child: ListTile(title: Text('Fila vazia.')))
              else
                for (final item in _queue.take(50))
                  Card(
                    child: ListTile(
                      leading: Icon(
                        item.status == LocalSyncStatus.done
                            ? Icons.check_circle_outline
                            : item.status == LocalSyncStatus.failed
                                ? Icons.error_outline
                                : Icons.sync,
                      ),
                      title: Text('${item.operation.name}: ${item.entityId}'),
                      subtitle: Text(
                        '${item.provider} • ${item.status.name} • tentativa ${item.attempts}'
                        '${item.lastError == null ? '' : '\n${item.lastError}'}',
                      ),
                      isThreeLine: item.lastError != null,
                      trailing: item.status == LocalSyncStatus.failed
                          ? IconButton(
                              tooltip: 'Tentar novamente',
                              onPressed: () async {
                                await _sync.retryNow(item.id);
                                await _load();
                              },
                              icon: const Icon(Icons.replay),
                            )
                          : null,
                    ),
                  ),
              const SizedBox(height: 24),
              Text(
                'Conflitos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_conflicts.isEmpty)
                const Card(
                  child: ListTile(title: Text('Nenhum conflito pendente.')),
                )
              else
                for (final conflict in _conflicts)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_arrows),
                      title: Text(conflict.entityId),
                      subtitle: Text(
                        '${conflict.provider}\n'
                        'local ${conflict.localVersion ?? '-'} • '
                        'remoto ${conflict.remoteVersion ?? '-'}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<ConflictResolution>(
                        onSelected: (value) => _resolve(conflict, value),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: ConflictResolution.keepLocal,
                            child: Text('Manter local'),
                          ),
                          PopupMenuItem(
                            value: ConflictResolution.keepRemote,
                            child: Text('Manter remoto'),
                          ),
                          PopupMenuItem(
                            value: ConflictResolution.keepBoth,
                            child: Text('Manter ambos'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
