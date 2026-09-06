import 'document_provider.dart';
import 'local_document_provider.dart';
import '../storage/local_document_catalog.dart';

class LocalLibraryIndexer {
  const LocalLibraryIndexer({
    required this.provider,
    required this.catalog,
  });

  final LocalDocumentProvider provider;
  final LocalDocumentCatalog catalog;

  Future<List<DocumentRef>> indexDirectory(String directoryPath) async {
    final documents = await provider.list(parentId: directoryPath);
    for (final document in documents) {
      await catalog.upsert(document);
    }
    return documents;
  }
}
