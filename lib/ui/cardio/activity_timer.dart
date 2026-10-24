import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import 'cardio_form.dart';

/// Icon for a cardio type or sport.
IconData activityIcon(String type) => switch (type) {
      'walk' => Icons.directions_walk,
      'bike' => Icons.directions_bike,
      'swim' => Icons.pool,
      'padel' || 'tennis' => Icons.sports_tennis,
      'soccer' => Icons.sports_soccer,
      'basketball' => Icons.sports_basketball,
      _ => Icons.directions_run,
    };

String activityLabel(String type) => type[0].toUpperCase() + type.substring(1);

/// Running clock for a live activity. Stop opens the cardio form with the time filled in.
// shortcut: the clock lives in memory, so killing the app loses it; persist the start time if that bites.
class ActivityTimer extends StatefulWidget {
  const ActivityTimer({super.key, required this.store, required this.type});

  final CardioStore store;
  final String type;

  @override
  State<ActivityTimer> createState() => _ActivityTimerState();
}

class _ActivityTimerState extends State<ActivityTimer> {
  final _start = DateTime.now();
  late final _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sec = DateTime.now().difference(_start).inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: Text(activityLabel(widget.type))),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(activityIcon(widget.type), size: 64),
          const SizedBox(height: 16),
          Text('${sec ~/ 3600}:${two(sec % 3600 ~/ 60)}:${two(sec % 60)}',
              style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => CardioForm(store: widget.store, type: widget.type, startedAt: _start, durationSec: sec),
            )),
          ),
        ]),
      ),
    );
  }
}
