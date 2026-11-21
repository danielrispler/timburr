import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/health_connect.dart';
import '../../data/live_recorder.dart';
import '../../data/treadmill.dart';
import '../cardio/run_page.dart';
import 'heart_rate_panel.dart';
import '../core/theme.dart';
import '../routines/start.dart';

/// Opens the recording screen: setup before Start, the live numbers during a recording. Does nothing without a recorder (tests).
/// [type] is 'run' (GPS) or 'treadmill' (time at the usual pace); a recording already in progress keeps its own.
void openRecorder(BuildContext context, Stores stores, {String type = 'run'}) {
  final recorder = liveRecorder;
  if (recorder == null) return;
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => RecordScreen(recorder: recorder, cardio: stores.cardio, type: recorder.type ?? type, checkFitbit: healthConnect?.check)));
}

/// The Run to prefill the Treadmill data form with: it carries the Fitbit's figures if a Health Connect [check] brings them within [timeout], else the
/// recording's own estimates (distance from the usual pace).
Future<CardioData> prefillTreadmillRun(CardioStore cardio, String id, {Future<Object?> Function()? check, Duration timeout = const Duration(seconds: 4)}) async {
  try {
    await check?.call().timeout(timeout);
  } catch (_) {} // a slow or failed check just leaves the estimate
  return cardio.watch(id).first;
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
/// A treadmill recording has no GPS: distance is Moving time at Daniel's usual treadmill pace (an estimate), and Finish ends with Treadmill data.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.recorder, required this.cardio, this.type = 'run', this.checkFitbit});

  final LiveRecorder recorder;
  final CardioStore cardio;
  final String type;

  /// The on-demand Fitbit check (Check Fitbit now), run before the Treadmill data step. Null without Health Connect.
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
    final ok = rec.active || treadmill || await rec.hasPermission(); // a treadmill recording needs no permission of its own
    if (ok && !rec.active && !treadmill) await rec.open();
    if (mounted) {
      setState(() {
        _allowed = ok;
        _checked = true;
      });
    }
  }

  Future<void> _allow() async {
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
      final run = await prefillTreadmillRun(widget.cardio, id, check: widget.checkFitbit);
      if (!mounted) return;
      final edits = await showDialog<Map<String, Object?>>(context: context, barrierDismissible: false, builder: (_) => TreadmillDataDialog(run: run));
      if (edits != null && edits.isNotEmpty) await widget.cardio.edit(id, edits);
      if (!mounted) return;
    }
    nav.pushReplacement(MaterialPageRoute(builder: (_) => RunPage(store: widget.cardio, id: id)));
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
                  ? 'Timburr times your run and estimates the distance from your usual treadmill pace, with the screen off too. '
                      'While recording, Android shows a notification so the phone keeps the recording alive. '
                      'No location is used. When you finish, you can type what the treadmill showed: distance, time, incline, steps and calories.'
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
            onPressed: () async => rec.start(widget.type, paceSecPerKm: treadmill ? usualTreadmillPace(await widget.cardio.watchAll().first) : null),
          ),
        ] else
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
            icon: const Icon(Icons.location_on),
            label: const Text('Allow location and notifications'),
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
      Center(child: Text(treadmill ? 'km (estimate at your usual pace)' : 'km')),
      const SizedBox(height: 24),
      Row(children: [
        if (!treadmill) stat('Pace /km', pace(s.currentPaceSecPerKm)),
        stat(treadmill ? 'Usual pace /km (estimate)' : 'Avg pace /km', pace(s.avgPaceSecPerKm)),
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

/// The Treadmill data step that ends a treadmill recording: what the treadmill showed, prefilled with the best estimates of [run] (the Fitbit's figures
/// if they arrived, else the estimate from the usual pace). Pops the fields Daniel changed, as SQL columns to values (see [treadmillEdits]); null for
/// Keep estimate. The caller saves them with `CardioStore.edit`, so each is an edited field that later merges and syncs never replace.
class TreadmillDataDialog extends StatefulWidget {
  const TreadmillDataDialog({super.key, required this.run});

  final CardioData run;

  @override
  State<TreadmillDataDialog> createState() => _TreadmillDataDialogState();
}

class _TreadmillDataDialogState extends State<TreadmillDataDialog> {
  late final Map<String, String> _initial = {
    'distance_km': widget.run.distanceKm?.toStringAsFixed(2) ?? '',
    'duration_sec': formatDuration(widget.run.durationSec),
    'incline_pct': widget.run.inclinePct == null ? '' : _num(widget.run.inclinePct!),
    'steps': widget.run.steps?.toString() ?? '',
    'calories': widget.run.calories?.toString() ?? '',
  };
  late final Map<String, TextEditingController> _c = {for (final e in _initial.entries) e.key: TextEditingController(text: e.value)};
  Map<String, String> _errors = {};

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    String t(String k) => _c[k]!.text;
    final errors = validateCardio(type: 'treadmill', distance: t('distance_km'), duration: t('duration_sec'), incline: t('incline_pct'), steps: t('steps'), calories: t('calories'));
    setState(() => _errors = errors);
    if (errors.isEmpty) Navigator.pop(context, treadmillEdits(_initial, {for (final e in _c.entries) e.key: e.value.text}));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String errorKey, String label, {TextInputType? keyboard}) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: _c[key],
            keyboardType: keyboard ?? const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, errorText: _errors[errorKey], border: const OutlineInputBorder()),
          ),
        );
    return AlertDialog(
      title: const Text('Treadmill data'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Type what the treadmill shows. The fields start as estimates; what you change is kept as you typed it.'),
          field('distance_km', 'distance', 'Distance (km)'),
          field('duration_sec', 'duration', 'Moving time', keyboard: TextInputType.datetime),
          field('incline_pct', 'incline', 'Incline % (optional)'),
          field('steps', 'steps', 'Steps (optional)', keyboard: TextInputType.number),
          field('calories', 'calories', 'Calories (optional)', keyboard: TextInputType.number),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep estimate')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
