import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/importer.dart';
import '../../data/sync.dart';
import '../cardio/cardio_stats.dart';
import '../import/import_screen.dart';

/// Header status: `synced`, `N pending`, `offline` or `error` (tap for the message).
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.engine});

  final SyncEngine engine;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([engine.error, engine.offline]),
        builder: (context, _) => StreamBuilder<int>(
          stream: engine.watchPending(),
          builder: (context, snap) {
            final error = engine.error.value;
            final pending = snap.data ?? 0;
            final label = engine.offline.value
                ? 'offline'
                : error != null
                    ? 'error'
                    : pending > 0
                        ? '$pending pending'
                        : 'synced';
            return TextButton(
              onPressed: error == null
                  ? null
                  : () => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(title: const Text('Sync error'), content: Text(error)),
                      ),
              child: Text(label),
            );
          },
        ),
      );
}

/// More tab: Import, Sync now and Sign out. Sign out needs 0 pending and wipes the local copy.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.engine, required this.catalog, required this.cardio});

  final CardioStore cardio;
  final SyncEngine? engine; // null when no Supabase project is configured
  final Catalog catalog;

  Future<void> _signOut(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final engine = this.engine!;
    final pending = await engine.pending();
    if (pending > 0) {
      messenger.showSnackBar(SnackBar(content: Text('Sync first: $pending changes are not uploaded yet.')));
      return;
    }
    await Supabase.instance.client.auth.signOut();
    await engine.wipe();
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Import'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImportScreen(importer: Importer(catalog.db, catalog), catalog: catalog),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.directions_run),
            title: const Text('Cardio stats'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardioStatsScreen(cardio: cardio))),
          ),
          if (engine case final engine?) ...[
            ListTile(leading: const Icon(Icons.sync), title: const Text('Sync now'), onTap: engine.sync),
            ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () => _signOut(context)),
          ],
        ],
      );
}

/// Shown once on a fresh install. Sign-ups are disabled on the project, so this only signs in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } catch (e) {
      setState(() => _error = e is AuthException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sign in')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _submit, child: const Text('Sign in')),
              ],
            ),
          ),
        ),
      );
}
