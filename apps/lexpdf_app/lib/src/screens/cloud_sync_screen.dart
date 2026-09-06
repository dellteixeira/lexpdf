import 'package:flutter/material.dart';

import '../core/backend/backend_config.dart';
import '../core/cloud/cloud_credential_store.dart';
import '../core/storage/local_cloud_account_store.dart';
import '../core/storage/local_database.dart';
import '../core/storage/local_sync_store.dart';
import 'cloud_files_screen.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({required this.db, super.key});

  final LocalDatabase db;

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  late final LocalCloudAccountStore _accounts;
  late final LocalSyncStore _sync;
  final CloudCredentialStore _credentials = const CloudCredentialStore();
  late Future<void> _loadFuture;
  List<LocalCloudAccount> _accountItems = const [];
  List<LocalSyncItem> _queue = const [];
  List<LocalSyncConflict> _conflicts = const [];

  @override
  void initState() {
    super.initState();
    _accounts = LocalCloudAccountStore(widget.db);
    _sync = LocalSyncStore(widget.db);
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final accounts = await _accounts.list();
    final queue = await _sync.list();
    final conflicts = await _sync.listConflicts(unresolvedOnly: true);
    if (!mounted) return;
    setState(() {
      _accountItems = accounts;
      _queue = queue;
      _conflicts = conflicts;
    });
  }

  Future<void> _addAccount() async {
    String provider = 'google_drive';
    final account = TextEditingController();
    final display = TextEditingController();
    final gateway = TextEditingController(
      text: BackendConfig.fromEnvironment.cloudGatewayUrl,
    );
    final token = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Conectar nuvem'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: provider,
                    decoration: const InputDecoration(labelText: 'Provedor'),
                    items: const [
                      DropdownMenuItem(value: 'google_drive', child: Text('Google Drive')),
                      DropdownMenuItem(value: 'onedrive', child: Text('OneDrive')),
                      DropdownMenuItem(value: 'icloud', child: Text('iCloud / File Provider')),
                      DropdownMenuItem(value: 'r2', child: Text('LexPDF Cloud / R2')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => provider = value);
                    },
                  ),
                  TextField(
                    controller: account,
                    decoration: const InputDecoration(labelText: 'ID da conta'),
                  ),
                  TextField(
                    controller: display,
                    decoration: const InputDecoration(labelText: 'Nome de exibição'),
                  ),
                  TextField(
                    controller: gateway,
                    decoration: const InputDecoration(labelText: 'URL do gateway'),
                  ),
                  TextField(
                    controller: token,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Token do gateway/OAuth',
                      helperText: 'Salvo apenas no armazenamento seguro do sistema.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      account.dispose();
      display.dispose();
      gateway.dispose();
      token.dispose();
      return;
    }
    final accountId = account.text.trim();
    final gatewayUrl = gateway.text.trim();
    final secret = token.text;
    if (accountId.isEmpty || gatewayUrl.isEmpty || secret.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta, gateway e token são obrigatórios.')),
        );
      }
    } else {
      final uri = Uri.tryParse(gatewayUrl);
      if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.host != 'localhost')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use um gateway HTTPS válido.')),
          );
        }
      } else {
        await _credentials.writeToken(
          provider: provider,
          accountId: accountId,
          token: secret,
        );
        await _accounts.upsert(
          LocalCloudAccount(
            provider: provider,
            accountId: accountId,
            displayName: display.text.trim().isEmpty ? accountId : display.text.trim(),
            gatewayUrl: gatewayUrl,
            status: 'connected',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        await _load();
      }
    }
    account.dispose();
    display.dispose();
    gateway.dispose();
    token.dispose();
  }

  Future<void> _remove(LocalCloudAccount account) async {
    await _credentials.deleteToken(
      provider: account.provider,
      accountId: account.accountId,
    );
    await _accounts.remove(account.provider, account.accountId);
    await _load();
  }

  Future<void> _resolve(LocalSyncConflict conflict, ConflictResolution resolution) async {
    await _sync.resolveConflict(conflict.id, resolution);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuvem e sincronização'),
        actions: [
          IconButton(onPressed: _addAccount, icon: const Icon(Icons.add_link), tooltip: 'Conectar conta'),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
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
              Text('Contas', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_accountItems.isEmpty)
                const Card(child: ListTile(title: Text('Nenhuma conta conectada.')))
              else
                for (final account in _accountItems)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(account.displayName),
                      subtitle: Text('${account.provider} • ${account.status}'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudFilesScreen(
                            account: account,
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
              Text('Fila de sincronização', style: Theme.of(context).textTheme.titleLarge),
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
                      subtitle: Text('${item.provider} • ${item.status.name} • tentativa ${item.attempts}'),
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
              Text('Conflitos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_conflicts.isEmpty)
                const Card(child: ListTile(title: Text('Nenhum conflito pendente.')))
              else
                for (final conflict in _conflicts)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_arrows),
                      title: Text(conflict.entityId),
                      subtitle: Text('${conflict.provider} • local ${conflict.localVersion ?? '-'} / remoto ${conflict.remoteVersion ?? '-'}'),
                      trailing: PopupMenuButton<ConflictResolution>(
                        onSelected: (value) => _resolve(conflict, value),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: ConflictResolution.keepLocal, child: Text('Manter local')),
                          PopupMenuItem(value: ConflictResolution.keepRemote, child: Text('Manter remoto')),
                          PopupMenuItem(value: ConflictResolution.keepBoth, child: Text('Manter ambos')),
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
