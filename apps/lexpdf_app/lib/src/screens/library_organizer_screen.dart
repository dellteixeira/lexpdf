import 'package:flutter/material.dart';

import '../core/documents/document_provider.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_pdf_navigation_store.dart';

class LibraryOrganizerScreen extends StatefulWidget {
  const LibraryOrganizerScreen({
    required this.catalog,
    required this.store,
    super.key,
  });

  final LocalDocumentCatalog catalog;
  final LocalPdfNavigationStore store;

  @override
  State<LibraryOrganizerScreen> createState() => _LibraryOrganizerScreenState();
}

class _LibraryOrganizerScreenState extends State<LibraryOrganizerScreen> {
  List<DocumentCollection> _collections = const [];
  List<DocumentRef> _documents = const [];
  String? _selectedCollectionId;
  Set<String> _members = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final collections = await widget.store.listCollections();
    final documents = await widget.catalog.list(limit: 1000);
    var members = <String>{};
    final selected = _selectedCollectionId;
    if (selected != null) {
      members = (await widget.store.listDocumentIdsInCollection(selected)).toSet();
    }
    if (!mounted) return;
    setState(() {
      _collections = collections;
      _documents = documents;
      _members = members;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizar biblioteca'),
        actions: [
          IconButton(
            tooltip: 'Nova coleção',
            onPressed: _createCollection,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.collections_bookmark_outlined),
                        title: Text('Coleções'),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _collections.length,
                          itemBuilder: (context, index) {
                            final collection = _collections[index];
                            return ListTile(
                              selected: collection.id == _selectedCollectionId,
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(collection.name),
                              onTap: () async {
                                _selectedCollectionId = collection.id;
                                await _reload();
                              },
                              trailing: IconButton(
                                tooltip: 'Excluir coleção',
                                onPressed: () => _deleteCollection(collection),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selectedCollectionId == null
                      ? const Center(
                          child: Text('Crie ou selecione uma coleção para organizar seus PDFs.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _documents.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final document = _documents[index];
                            final checked = _members.contains(document.id);
                            return Card(
                              child: ListTile(
                                leading: Checkbox(
                                  value: checked,
                                  onChanged: (_) => _toggleMembership(document, checked),
                                ),
                                title: Text(document.name),
                                subtitle: _TagsRow(
                                  document: document,
                                  store: widget.store,
                                  onChanged: () => setState(() {}),
                                ),
                                onTap: () => _toggleMembership(document, checked),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _createCollection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova coleção'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final collection = await widget.store.createCollection(name);
    _selectedCollectionId = collection.id;
    await _reload();
  }

  Future<void> _deleteCollection(DocumentCollection collection) async {
    await widget.store.deleteCollection(collection.id);
    if (_selectedCollectionId == collection.id) _selectedCollectionId = null;
    await _reload();
  }

  Future<void> _toggleMembership(DocumentRef document, bool currentlyMember) async {
    final collectionId = _selectedCollectionId;
    if (collectionId == null) return;
    if (currentlyMember) {
      await widget.store.removeDocumentFromCollection(collectionId, document.id);
    } else {
      await widget.store.addDocumentToCollection(collectionId, document.id);
    }
    await _reload();
  }
}

class _TagsRow extends StatefulWidget {
  const _TagsRow({
    required this.document,
    required this.store,
    required this.onChanged,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore store;
  final VoidCallback onChanged;

  @override
  State<_TagsRow> createState() => _TagsRowState();
}

class _TagsRowState extends State<_TagsRow> {
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tags = await widget.store.listTags(widget.document.id);
    if (mounted) setState(() => _tags = tags);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in _tags)
          InputChip(
            label: Text(tag),
            onDeleted: () async {
              await widget.store.removeTag(widget.document.id, tag);
              await _load();
              widget.onChanged();
            },
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('tag'),
          onPressed: _addTag,
        ),
      ],
    );
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tag para ${widget.document.name}'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    await widget.store.addTag(widget.document.id, value);
    await _load();
    widget.onChanged();
  }
}
