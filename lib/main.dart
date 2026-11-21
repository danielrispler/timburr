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
import 'data/health_connect.dart';
import 'data/live_recorder.dart';
import 'data/platform_recording.dart';
import 'data/supabase_remote.dart';
import 'data/sync.dart';
import 'data/routines.dart';
import 'data/workouts.dart';
import 'ui/core/app_shell.dart';
import 'ui/core/theme.dart';
import 'ui/import/shared_files.dart';
import 'ui/import/strava_import_screen.dart';
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
  final cardio = CardioStore(db, onSaved: sync?.sync);
  // A recording the app was killed in comes back paused; the Home and Running tabs offer to resume it.
  liveRecorder = LiveRecorder(source: GeolocatorSource(), service: ForegroundRecordingService(), stepSource: PedometerSource(), journal: DbJournal(db), cardio: cardio);
  await liveRecorder!.restore();
  runApp(TimburrApp(catalog: Catalog(db), routines: RoutineStore(db), workouts: workouts, cardio: cardio, health: HealthConnect(cardio, workouts), sync: sync));
}

final _navigatorKey = GlobalKey<NavigatorState>();

class TimburrApp extends StatefulWidget {
  const TimburrApp({super.key, required this.catalog, required this.routines, required this.workouts, required this.cardio, required this.health, this.sync});

  final Catalog catalog;
  final RoutineStore routines;
  final WorkoutStore workouts;
  final CardioStore cardio;
  final HealthConnect health;
  final SyncEngine? sync;

  @override
  State<TimburrApp> createState() => _TimburrAppState();
}

class _TimburrAppState extends State<TimburrApp> {
  late final ShareIntake _share;
  late final AppLifecycleListener _lifecycle;

  /// A GPX/TCX shared to Timburr opens the import preview; backing out saves nothing.
  void _openShared(List<SharedFile> files) =>
      _navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => StravaImportScreen(cardio: widget.cardio, shared: files)));

  @override
  void initState() {
    super.initState();
    _share = ShareIntake(_openShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _share.checkLaunch());
    // The Fitbit's sessions fill in Runs on start and resume; does nothing until Daniel connects.
    widget.health.checkQuietly();
    _lifecycle = AppLifecycleListener(onResume: widget.health.checkQuietly);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog, routines = widget.routines, workouts = widget.workouts, cardio = widget.cardio, health = widget.health, sync = widget.sync;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: buildDarkTheme(),
      home: sync == null
          ? AppShell(catalog: catalog, routines: routines, workouts: workouts, cardio: cardio, health: health)
          : _AuthGate(catalog: catalog, routines: routines, workouts: workouts, cardio: cardio, health: health, sync: sync),
    );
  }
}

/// Login on a fresh install; afterwards the app, syncing on start, resume, every 5 minutes and when back online.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.catalog, required this.routines, required this.workouts, required this.cardio, required this.health, required this.sync});

  final Catalog catalog;
  final RoutineStore routines;
  final WorkoutStore workouts;
  final CardioStore cardio;
  final HealthConnect health;
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
      _signedIn ? AppShell(catalog: widget.catalog, routines: widget.routines, workouts: widget.workouts, cardio: widget.cardio, health: widget.health, sync: widget.sync) : const LoginScreen();
}
