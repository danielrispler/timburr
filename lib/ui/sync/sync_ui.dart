import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/importer.dart';
import '../../data/sync.dart';
import '../../data/workouts.dart';
import '../core/theme.dart';
import '../backup/backup_screen.dart';
import '../cardio/cardio_stats.dart';
import '../exercises/exercise_detail.dart';
import '../exercises/exercise_picker.dart';
import '../import/import_screen.dart';

/// Header status: `synced`, `N pending`, `offline` or `error` (tap for the message).
class SyncBadge extends StatefulWidget {
  const SyncBadge({super.key, required this.engine});

  final SyncEngine engine;

  @override
  State<SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<SyncBadge> {
  // Created once: a new stream per status change would resubscribe the query.
  late final Stream<int> _pending = widget.engine.watchPending();

  SyncEngine get engine => widget.engine;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([engine.error, engine.offline]),
        builder: (context, _) => StreamBuilder<int>(
          stream: _pending,
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

/// More tab: Import, Backup / Restore, Sync now and Sign out. Sign out needs 0 pending and wipes the local copy.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.engine, required this.catalog, required this.cardio, required this.workouts});

  final CardioStore cardio;
  final WorkoutStore workouts;
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
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException {
      // gotrue drops the local session before the network call, so offline sign-out is still a sign-out.
    } finally {
      await engine.wipe();
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          TileGroup(title: 'Data', children: [
          ListTile(
            leading: const IconTile(Icons.fitness_center),
            title: const Text('Exercises'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Exercises')),
                body: ExercisePicker(
                  catalog: catalog,
                  onSelected: (e) => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ExerciseDetail(catalog: catalog, entry: e, workouts: workouts))),
                  onCreate: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => CustomExerciseForm(catalog: catalog))),
                ),
              ),
            )),
          ),
          ListTile(
            leading: const IconTile(Icons.file_download),
            title: const Text('Import'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImportScreen(importer: Importer(catalog.db, catalog), catalog: catalog),
            )),
          ),
          ListTile(
            leading: const IconTile(Icons.directions_run),
            title: const Text('Cardio stats'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardioStatsScreen(cardio: cardio))),
          ),
          ListTile(
            leading: const IconTile(Icons.backup),
            title: const Text('Backup / Restore'),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => BackupScreen(db: catalog.db, engine: engine))),
          ),
          ]),
          if (engine case final engine?)
            TileGroup(title: 'Account', children: [
              ListTile(leading: const IconTile(Icons.sync), title: const Text('Sync now'), onTap: engine.sync),
              ListTile(leading: const IconTile(Icons.logout), title: const Text('Sign out'), onTap: () => _signOut(context)),
            ]),
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
                const SizedBox(height: 16),
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
