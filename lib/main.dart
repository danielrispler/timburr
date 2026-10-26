import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/cardio.dart';
import 'data/catalog.dart';
import 'data/db.dart';
import 'data/error_log.dart';
import 'data/supabase_remote.dart';
import 'data/sync.dart';
import 'data/routines.dart';
import 'data/workouts.dart';
import 'ui/core/app_shell.dart';
import 'ui/core/theme.dart';
import 'ui/sync/sync_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDb();
  final info = await PackageInfo.fromPlatform();
  final errors = errorLog = ErrorLog(db, appVersion: '${info.version}+${info.buildNumber}${kReleaseMode ? '' : ' debug'}');
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    errors.record('flutter', d.exception, d.stack, {'library': d.library, 'context': d.context?.toString(), 'silent': d.silent});
  };
  PlatformDispatcher.instance.onError = (e, st) {
    errors.record('platform', e, st);
    return true;
  };
  SyncEngine? sync;
  if (supabaseUrl.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
    sync = SyncEngine(
      db,
      SupabaseRemote(Supabase.instance.client),
      errors: errors,
      isOnline: () async => !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none),
    );
  }
  // Finishing a workout triggers sync (no-op without a Supabase project).
  final workouts = WorkoutStore(db, onFinished: sync?.sync);
  runApp(TimburrApp(catalog: Catalog(db), routines: RoutineStore(db), workouts: workouts, cardio: CardioStore(db, onSaved: sync?.sync), sync: sync));
}

class TimburrApp extends StatelessWidget {
  const TimburrApp({super.key, required this.catalog, required this.routines, required this.workouts, required this.cardio, this.sync});

  final Catalog catalog;
  final RoutineStore routines;
  final WorkoutStore workouts;
  final CardioStore cardio;
  final SyncEngine? sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: buildDarkTheme(),
      home: sync == null
          ? AppShell(catalog: catalog, routines: routines, workouts: workouts, cardio: cardio)
          : _AuthGate(catalog: catalog, routines: routines, workouts: workouts, cardio: cardio, sync: sync!),
    );
  }
}

/// Login on a fresh install; afterwards the app, syncing on start, resume, every 5 minutes and when back online.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.catalog, required this.routines, required this.workouts, required this.cardio, required this.sync});

  final Catalog catalog;
  final RoutineStore routines;
  final WorkoutStore workouts;
  final CardioStore cardio;
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
      _signedIn ? AppShell(catalog: widget.catalog, routines: widget.routines, workouts: widget.workouts, cardio: widget.cardio, sync: widget.sync) : const LoginScreen();
}
