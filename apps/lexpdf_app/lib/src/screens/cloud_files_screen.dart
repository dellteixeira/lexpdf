import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cloud/cloud_gateway_document_provider.dart';
import '../core/documents/document_provider.dart';
import '../core/storage/local_cloud_account_store.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_sync_store.dart';

class CloudFilesScreen extends StatefulWidget {
  const CloudFilesScreen({
    required this.account,
    this.catalog,
    this.syncStore,
    super.key,
  });

  final LocalCloudAccount account;
  final LocalDocumentCatalog? catalog;
  final LocalSyncStore? syncStore;

  @override
  State<CloudFilesScreen> createState() => _CloudFilesScreenState();
}

class _CloudFilesScreenState extends State<CloudFilesScreen> {
  CloudGatewayDocumentProvider? _provider;
  Future<List<DocumentRef>>? _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final root = await getApplicationSupportDirectory();
    final cache = Directory(
      '${root.path}${Platform.pathSeparator}cloud-cache${Platform.pathSeparator}${widget.account.provider}${Platform.pathSeparator}${widget.account.accountId}',
    );
    final provider = CloudGatewayDocumentProvider(
      kind: _kind(widget.account.provider),
      accountId: widget.account.accountId,
      gatewayBaseUrl: Uri.parse(widget.account.gatewayUrl),
      cacheDirectory: cache,
    );
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _future = provider.list();
    });
  }

  Future<void> _refresh() async {
    final provider = _provider;
    if (provider == null) return;
    setState(() => _future = provider.list());
    await _future;
  }

  Future<void> _download(DocumentRef document) async {
    final provider = _provider;
    if (provider == null || _busy) return;
    setState(() => _busy = true);
    final job = await widget.syncStore?.enqueue(
      entityId: document.id,
      provider: widget.account.provider,
      operation: LocalSyncOperation.download,
      payload: {
        'accountId': widget.account.accountId,
        'remoteId': document.remoteId ?? document.id,
      },
    );
    if (job != null) await widget.syncStore!.markRunning(job.id);
    try {
      final path = await provider.ensureLocalCopy(document);
      final cached = DocumentRef(
        id: document.id,
        name: document.name,
        provider: document.provider,
        localPath: path,
        remoteId: document.remoteId,
        remotePath: document.remotePath,
        availableOffline: true,
        syncState: DocumentSyncState.synced,
      );
      await widget.catalog?.upsert(cached);
      if (job != null) await widget.syncStore!.markDone(job.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disponível offline em: $path')),
      );
    } catch (error) {
      if (job != null) {
        await widget.syncStore!.markFailed(
          job.id,
          error,
          maxAttempts: 5,
          retryAfter: const Duration(seconds: 5),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download não concluído: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final provider = _provider;
    if (provider == null || _busy) return;
    const group = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    setState(() => _busy = true);
    final job = await widget.syncStore?.enqueue(
      entityId: file.path,
      provider: widget.account.provider,
      operation: LocalSyncOperation.upload,
      payload: {
        'accountId': widget.account.accountId,
        'localPath': file.path,
        'name': file.name,
      },
    );
    if (job != null) await widget.syncStore!.markRunning(job.id);
    try {
      final uploaded = await provider.upload(file.path);
      await widget.catalog?.upsert(uploaded);
      if (job != null) await widget.syncStore!.markDone(job.id);
      await _refresh();
    } catch (error) {
      if (job != null) {
        await widget.syncStore!.markFailed(
          job.id,
          error,
          maxAttempts: 5,
          retryAfter: const Duration(seconds: 5),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload não concluído: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account.displayName),
        actions: [
          IconButton(
            tooltip: 'Enviar PDF',
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _future == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<DocumentRef>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Não foi possível listar a nuvem: ${snapshot.error}'),
                    ),
                  );
                }
                final documents = snapshot.data ?? const [];
                if (documents.isEmpty) {
                  return const Center(child: Text('Nenhum PDF neste local.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: documents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(document.name),
                        subtitle: Text(document.remotePath ?? 'Arquivo remoto'),
                        trailing: IconButton(
                          tooltip: 'Disponibilizar offline',
                          onPressed: _busy ? null : () => _download(document),
                          icon: const Icon(Icons.download_for_offline_outlined),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  DocumentProviderKind _kind(String provider) => switch (provider) {
        'google_drive' => DocumentProviderKind.googleDrive,
        'onedrive' => DocumentProviderKind.oneDrive,
        'icloud' => DocumentProviderKind.iCloud,
        'r2' => DocumentProviderKind.r2,
        _ => throw StateError('Unsupported cloud provider: $provider'),
      };
}
