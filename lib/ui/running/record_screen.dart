import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/health_connect.dart';
import '../../data/live_recorder.dart';
import '../cardio/run_page.dart';
import 'heart_rate_panel.dart';
import '../core/theme.dart';
import '../routines/start.dart';

/// Opens the recording screen: setup before Start, the live numbers during a recording. Does nothing without a recorder (tests).
/// [type] is 'run' (GPS) or 'treadmill' (steps); a recording already in progress keeps its own.
void openRecorder(BuildContext context, Stores stores, {String type = 'run'}) {
  final recorder = liveRecorder;
  if (recorder == null) return;
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => RecordScreen(recorder: recorder, cardio: stores.cardio, type: recorder.type ?? type, checkFitbit: healthConnect?.check)));
}

/// The distance (km) to prefill Check distance with: the Fitbit's figure if a Health Connect [check] brings it within [timeout], else the phone's estimate.
Future<double?> prefillDistanceKm(CardioStore cardio, String id, {Future<Object?> Function()? check, Duration timeout = const Duration(seconds: 4)}) async {
  try {
    await check?.call().timeout(timeout);
  } catch (_) {} // a slow or failed check just leaves the phone's estimate
  return (await cardio.watch(id).first).distanceKm;
}

/// A tile that resumes the recording in progress; empty when there is none.
class RecordingBanner extends StatelessWidget {
  const RecordingBanner({super.key, required this.stores});

  final Stores stores;

  @override
  Widget build(BuildContext context) {
    final recorder = liveRecorder;
    if (recorder == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) => !recorder.active
          ? const SizedBox.shrink()
          : TileGroup(title: 'Today', children: [
              ListTile(
                leading: const IconTile(Icons.directions_run),
                title: Text(recorder.type == 'treadmill' ? 'Treadmill run in progress' : 'Run in progress'),
                subtitle: const Text('Tap to resume'),
                onTap: () => openRecorder(context, stores), // keeps the type of the recording in progress
              ),
            ]),
    );
  }
}

/// Recording: big Moving time, distance, current and average pace, a GPS indicator, Pause/Resume and Finish.
/// A treadmill recording has no GPS: distance is the phone's steps times the calibrated stride, and Finish ends with Check distance.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.recorder, required this.cardio, this.type = 'run', this.checkFitbit});

  final LiveRecorder recorder;
  final CardioStore cardio;
  final String type;

  /// The on-demand Fitbit check (Check Fitbit now), run before the Check distance step. Null without Health Connect.
  final Future<Object?> Function()? checkFitbit;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final Timer _tick;
  bool _allowed = false, _busy = false;
  bool _checked = false;
  String? _problem;

  LiveRecorder get rec => widget.recorder;
  bool get treadmill => widget.type == 'treadmill';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _prepare();
  }

  @override
  void dispose() {
    _tick.cancel();
    if (!rec.active) rec.close();
    super.dispose();
  }

  /// Without asking: if location is already allowed, start listening so the GPS indicator works before Start.
  Future<void> _prepare() async {
    final ok = rec.active || await (treadmill ? rec.hasStepPermission() : rec.hasPermission());
    if (ok && !rec.active && !treadmill) await rec.open();
    if (mounted) {
      setState(() {
        _allowed = ok;
        _checked = true;
      });
    }
  }

  Future<void> _allow() async {
    if (treadmill) {
      final ok = await rec.requestStepPermission();
      if (!mounted) return;
      setState(() {
        _allowed = ok;
        _problem = ok ? null : 'Timburr needs physical activity access to count your steps. Allow it in the phone\'s Settings, under Apps, Timburr, Permissions.';
      });
      return;
    }
    final p = await rec.requestPermission();
    if (p == PositionPermission.granted) await rec.open();
    if (!mounted) return;
    setState(() {
      _allowed = p == PositionPermission.granted;
      _problem = switch (p) {
        PositionPermission.granted => null,
        PositionPermission.servicesOff => 'Location is switched off. Turn it on in the phone\'s quick settings, then try again.',
        PositionPermission.deniedForever => 'Location is blocked for Timburr. Allow it in the phone\'s Settings, under Apps, Timburr, Permissions.',
        PositionPermission.denied => 'Timburr needs your location to record a run.',
      };
    });
  }

  Future<void> _finish() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(treadmill ? 'Finish this treadmill run?' : 'Finish this run?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    if (choice == 'discard') {
      await rec.discard();
      if (mounted) nav.pop();
      return;
    }
    final id = await rec.finish();
    if (!mounted) return;
    if (id == null) return nav.pop();
    if (treadmill) {
      final km = await _checkDistance(id, await prefillDistanceKm(widget.cardio, id, check: widget.checkFitbit));
      if (km != null) await widget.cardio.checkDistance(id, km: km, steps: rec.finishedSteps);
      if (!mounted) return;
    }
    nav.pushReplacement(MaterialPageRoute(builder: (_) => RunPage(store: widget.cardio, id: id)));
  }

  /// The Check distance step, prefilled with [estimate]: the best estimate (the Fitbit's figure if it has arrived, else the phone's) to correct with the treadmill's number. Null to keep the estimate.
  Future<double?> _checkDistance(String id, double? estimate) async {
    if (!mounted) return null;
    final field = TextEditingController(text: estimate?.toStringAsFixed(2) ?? '');
    final km = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Check distance'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Type the distance the treadmill shows. Timburr learns your stride from it.'),
          const SizedBox(height: 12),
          TextField(
            controller: field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Distance (km)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep estimate')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(field.text.trim().replaceAll(',', '.'));
              if (v != null && v > 0) Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    field.dispose();
    return km;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: rec,
        builder: (context, _) {
          final s = rec.snapshot;
          return Scaffold(
          appBar: AppBar(title: Text(treadmill ? 'Record treadmill run' : 'Record run')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: !_checked
                    ? const Center(child: CircularProgressIndicator())
                    : s != null
                        ? _live(context, s)
                        : _setup(context),
              ),
            ),
          ),
        );
        },
      );

  Widget _setup(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              treadmill
                  ? 'Timburr counts your steps with the phone to estimate the distance, with the screen off too. '
                      'While recording, Android shows a notification so the phone keeps the recording alive. '
                      'No location is used. When you finish, you type the treadmill\'s distance and Timburr learns your stride.'
                  : 'Timburr uses your location to measure distance and draw the route, even with the screen off. '
              'While recording, Android shows a notification so the phone keeps the recording alive. '
              'Your route stays on this phone and in your own Supabase project.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        HeartRateSetup(recorder: rec),
        if (_allowed) ...[
          if (!treadmill) ...[Center(child: _GpsChip(rec.gps)), const SizedBox(height: 16)],
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
            onPressed: () async => rec.start(widget.type, strideM: treadmill ? (await widget.cardio.settings.watch().first)?.strideM : null),
          ),
        ] else
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
            icon: const Icon(Icons.location_on),
            label: Text(treadmill ? 'Allow step counting and notifications' : 'Allow location and notifications'),
            onPressed: _allow,
          ),
      ]);

  Widget _live(BuildContext context, RunSnapshot s) {
    final theme = Theme.of(context);
    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: theme.textTheme.headlineLarge, maxLines: 1),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
        );
    String pace(double? p) => p == null ? '--:--' : formatPace(p);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (!treadmill) ...[Center(child: _GpsChip(s.gps)), const SizedBox(height: 16)],
      Center(child: Text(formatDuration(s.movingSec), style: theme.textTheme.displayLarge?.copyWith(fontSize: 88, fontFeatures: const [FontFeature.tabularFigures()]))),
      Center(
        child: Text(
          s.paused ? 'Paused' : s.autoPaused ? 'Auto-paused' : 'Moving time · elapsed ${formatDuration(s.elapsedSec)}',
          style: theme.textTheme.titleMedium?.copyWith(color: s.paused || s.autoPaused ? theme.colorScheme.tertiary : null),
        ),
      ),
      const SizedBox(height: 32),
      Center(child: Text((s.distanceM / 1000).toStringAsFixed(2), style: theme.textTheme.displayLarge?.copyWith(fontSize: 72))),
      Center(child: Text(treadmill ? 'km (estimated from steps)' : 'km')),
      const SizedBox(height: 24),
      Row(children: [
        if (treadmill) stat('Steps', '${s.steps}') else stat('Pace /km', pace(s.currentPaceSecPerKm)),
        stat('Avg pace /km', pace(s.avgPaceSecPerKm)),
      ]),
      const SizedBox(height: 16),
      LiveHeartRate(recorder: rec, snapshot: s),
      const SizedBox(height: 32),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        icon: const Icon(Icons.flag),
        label: Text('Lap (${rec.lapCount})'),
        onPressed: _busy || s.paused ? null : rec.lap,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            icon: Icon(s.paused ? Icons.play_arrow : Icons.pause),
            label: Text(s.paused ? 'Resume' : 'Pause'),
            onPressed: _busy ? null : () => s.paused ? rec.resume() : rec.pause(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            icon: const Icon(Icons.stop),
            label: const Text('Finish'),
            onPressed: _busy ? null : _finish,
          ),
        ),
      ]),
    ]);
  }
}

class _GpsChip extends StatelessWidget {
  const _GpsChip(this.signal);

  final GpsSignal signal;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (signal) {
      GpsSignal.good => ('GPS signal good', Colors.green, Icons.gps_fixed),
      GpsSignal.weak => ('GPS signal weak', Colors.orange, Icons.gps_not_fixed),
      GpsSignal.none => ('Waiting for GPS', Colors.red, Icons.gps_off),
    };
    return Chip(avatar: Icon(icon, color: color, size: 18), label: Text(label));
  }
}
