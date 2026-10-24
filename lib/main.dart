import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/catalog.dart';
import 'data/db.dart';
import 'data/supabase_remote.dart';
import 'data/sync.dart';
import 'ui/core/app_shell.dart';
import 'ui/sync/sync_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDb();
  SyncEngine? sync;
  if (supabaseUrl.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
    sync = SyncEngine(
      db,
      SupabaseRemote(Supabase.instance.client),
      isOnline: () async => !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none),
    );
  }
  runApp(TimburrApp(catalog: Catalog(db), sync: sync));
}

class TimburrApp extends StatelessWidget {
  const TimburrApp({super.key, required this.catalog, this.sync});

  final Catalog catalog;
  final SyncEngine? sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, brightness: Brightness.dark),
      ),
      home: sync == null ? AppShell(catalog: catalog) : _AuthGate(catalog: catalog, sync: sync!),
    );
  }
}

/// Login on a fresh install; afterwards the app, syncing on start, resume, every 5 minutes and when back online.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.catalog, required this.sync});

  final Catalog catalog;
  final SyncEngine sync;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _authSub;
  late final StreamSubscription<List<ConnectivityResult>> _netSub;
  late final AppLifecycleListener _lifecycle;
  late final Timer _timer;

  bool get _signedIn => _auth.currentSession != null;

  void _sync() {
    if (_signedIn) widget.sync.sync();
  }

  @override
  void initState() {
    super.initState();
    _authSub = _auth.onAuthStateChange.listen((s) {
      setState(() {});
      if (s.event == AuthChangeEvent.signedIn) _sync();
    });
    _netSub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) _sync();
    });
    _lifecycle = AppLifecycleListener(onResume: _sync);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _sync());
    _sync();
  }

  @override
  void dispose() {
    _authSub.cancel();
    _netSub.cancel();
    _lifecycle.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _signedIn ? AppShell(catalog: widget.catalog, sync: widget.sync) : const LoginScreen();
}
