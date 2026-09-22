import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/backend/backend_config.dart';
import '../core/storage/local_cloud_account_store.dart';
import '../core/storage/local_database.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({required this.database, super.key});

  final LocalDatabase database;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  Object? _error;
  String? _message;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        await _client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      });

  Future<void> _signUp() => _run(() async {
        await _client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
      });

  Future<void> _signOut() => _run(() => _client.auth.signOut());

  Future<void> _activateLexPdfCloud() => _run(() async {
        const config = BackendConfig.fromEnvironment;
        if (!config.hasCloudGateway) {
          throw StateError('LexPDF Cloud gateway is not configured.');
        }
        final accountUser = _client.auth.currentUser;
        if (accountUser?.email?.trim().isNotEmpty != true) {
          throw StateError('Entre na sua conta antes de ativar o LexPDF Cloud.');
        }
        final store = LocalCloudAccountStore(widget.database);
        await store.upsert(
          LocalCloudAccount(
            provider: 'r2',
            accountId: 'default',
            displayName: 'LexPDF Cloud',
            gatewayUrl: config.cloudGatewayUrl,
            status: 'connected',
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        if (mounted) {
          setState(() {
            _message = 'LexPDF Cloud ativado. A sessão da sua conta será usada automaticamente.';
          });
        }
      });

  @override
  Widget build(BuildContext context) {
    final sessionUser = _client.auth.currentUser;
    final user = sessionUser?.email?.trim().isNotEmpty == true
        ? sessionUser
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Conta LexPDF')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (user != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(user.email ?? 'Conta autenticada'),
                subtitle: const Text(
                  'Sessão Supabase ativa. O LexPDF Cloud usa esta sessão automaticamente.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _activateLexPdfCloud,
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: const Text('Ativar LexPDF Cloud'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair'),
                ),
              ],
            ),
          ] else ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.auto_awesome_outlined),
                title: Text('A IA não exige conta'),
                subtitle: Text(
                  'O LexPDF usa uma credencial técnica local do próprio '
                  'dispositivo para a IA online. Não há login para usar IA. '
                  'Conta continua necessária apenas para recursos pessoais '
                  'de nuvem e sincronização.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'E-mail',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Senha',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Entrar'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _signUp,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Criar conta'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'O aplicativo continua totalmente utilizável offline sem login. A conta é necessária apenas para sincronização e serviços online.',
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              'Não foi possível concluir: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
