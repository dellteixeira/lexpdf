import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/backend/backend_config.dart';
import 'src/core/documents/native_pdf_open_service.dart';
import 'src/core/storage/local_database.dart';
import 'src/core/storage/local_database_key_manager.dart';
import 'src/lexpdf_app.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_LexPdfBootstrap(arguments: List<String>.unmodifiable(args)));
}

class _LexPdfBootstrap extends StatefulWidget {
  const _LexPdfBootstrap({required this.arguments});

  final List<String> arguments;

  @override
  State<_LexPdfBootstrap> createState() => _LexPdfBootstrapState();
}

class _LexPdfBootstrapState extends State<_LexPdfBootstrap> {
  late Future<_BootstrapData> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<_BootstrapData> _initialize() async {
    // PDFium/pdfrx remains a Windows-only renderer. Android PDFs are opened
    // by Apryse DocumentActivity in a separate native process.
    if (Platform.isWindows) {
      await pdfrxFlutterInitialize();
    }

    const backend = BackendConfig.fromEnvironment;
    if (backend.hasSupabase) {
      await Supabase.initialize(
        url: backend.supabaseUrl,
        publishableKey: backend.supabasePublishableKey,
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    await supportDirectory.create(recursive: true);
    final databasePath =
        '${supportDirectory.path}${Platform.pathSeparator}lexpdf.sqlite3';
    final key = await const LocalDatabaseKeyManager().loadOrCreate(databasePath);
    final database = LocalDatabase.openEncrypted(databasePath, key);
    final args = widget.arguments;
    final initialPdfPath = NativePdfOpenService.pdfPathFromArgs(args);

    return _BootstrapData(
      database: database,
      initialPdfPath: initialPdfPath,
    );
  }

  void _retry() {
    setState(() => _startup = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapData>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final data = snapshot.requireData;
          return LexPdfApp(
            database: data.database,
            initialPdfPath: data.initialPdfPath,
          );
        }

        if (snapshot.hasError) {
          return _StartupFrame(error: snapshot.error, onRetry: _retry);
        }

        return const _StartupFrame();
      },
    );
  }
}

class _BootstrapData {
  const _BootstrapData({
    required this.database,
    required this.initialPdfPath,
  });

  final LocalDatabase database;
  final String? initialPdfPath;
}

class _StartupFrame extends StatelessWidget {
  const _StartupFrame({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LexPDF',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315B8A)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8AB4F8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, size: 58),
                    const SizedBox(height: 16),
                    Text(
                      'LexPDF',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    if (!failed) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text(
                        'Preparando seus documentos…',
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Icon(
                        Icons.error_outline,
                        size: 36,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Não foi possível iniciar o LexPDF.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$error',
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
