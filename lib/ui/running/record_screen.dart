import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/live_recorder.dart';
import '../cardio/run_page.dart';
import '../core/theme.dart';
import '../routines/start.dart';

/// Opens the recording screen: setup before Start, the live numbers during a recording. Does nothing without a recorder (tests).
void openRecorder(BuildContext context, Stores stores) {
  final recorder = liveRecorder;
  if (recorder == null) return;
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => RecordScreen(recorder: recorder, cardio: stores.cardio)));
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
                title: const Text('Run in progress'),
                subtitle: const Text('Tap to resume'),
                onTap: () => openRecorder(context, stores),
              ),
            ]),
    );
  }
}

/// Outdoor recording: big Moving time, distance, current and average pace, a GPS indicator, Pause/Resume and Finish.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.recorder, required this.cardio});

  final LiveRecorder recorder;
  final CardioStore cardio;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final Timer _tick;
  bool _allowed = false, _busy = false;
  bool _checked = false;
  String? _problem;

  LiveRecorder get rec => widget.recorder;

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
    final ok = rec.active || await rec.hasPermission();
    if (ok && !rec.active) await rec.open();
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
        title: const Text('Finish this run?'),
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
    nav.pushReplacement(MaterialPageRoute(builder: (_) => RunPage(store: widget.cardio, id: id)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: rec,
        builder: (context, _) {
          final s = rec.snapshot;
          return Scaffold(
          appBar: AppBar(title: const Text('Record run')),
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
              'Timburr uses your location to measure distance and draw the route, even with the screen off. '
              'While recording, Android shows a notification so the phone keeps the recording alive. '
              'Your route stays on this phone and in your own Supabase project.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        if (_allowed) ...[
          Center(child: _GpsChip(rec.gps)),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
            onPressed: () => rec.start('run'),
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
      Center(child: _GpsChip(s.gps)),
      const SizedBox(height: 16),
      Center(child: Text(formatDuration(s.movingSec), style: theme.textTheme.displayLarge?.copyWith(fontSize: 88, fontFeatures: const [FontFeature.tabularFigures()]))),
      Center(
        child: Text(
          s.paused ? 'Paused' : s.autoPaused ? 'Auto-paused' : 'Moving time · elapsed ${formatDuration(s.elapsedSec)}',
          style: theme.textTheme.titleMedium?.copyWith(color: s.paused || s.autoPaused ? theme.colorScheme.tertiary : null),
        ),
      ),
      const SizedBox(height: 32),
      Center(child: Text((s.distanceM / 1000).toStringAsFixed(2), style: theme.textTheme.displayLarge?.copyWith(fontSize: 72))),
      const Center(child: Text('km')),
      const SizedBox(height: 24),
      Row(children: [stat('Pace /km', pace(s.currentPaceSecPerKm)), stat('Avg pace /km', pace(s.avgPaceSecPerKm))]),
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
