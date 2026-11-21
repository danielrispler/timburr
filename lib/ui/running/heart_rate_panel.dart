import 'package:flutter/material.dart';

import '../../data/heart_rate.dart';
import '../../data/live_recorder.dart';

/// Colour of a zone, 1 (easy) to 5 (max).
Color zoneColor(int zone) => const [Colors.blueGrey, Colors.green, Colors.amber, Colors.orange, Colors.red][zone.clamp(1, 5) - 1];

/// Live heart rate and zone during a recording, with the link's problem in words when there is one. Used by the outdoor and the treadmill view.
class LiveHeartRate extends StatelessWidget {
  const LiveHeartRate({super.key, required this.recorder, required this.snapshot});

  final LiveRecorder recorder;
  final RunSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = recorder.hrState;
    final bpm = snapshot.hr, zone = snapshot.hrZone;
    if (link == HrLink.off && bpm == null) return const SizedBox.shrink();
    final note = switch (link) {
      HrLink.notFound => 'Band not found. On the Fitbit Air, turn on "Always visible" under Share heart rate in Google Health. Another app, like Strava, may be holding the connection.',
      HrLink.needsPairing => 'The band wants to be paired before it shares heart rate.',
      HrLink.reconnecting => 'Heart rate lost. Reconnecting; the run keeps recording.',
      HrLink.searching => 'Looking for the band...',
      _ => null,
    };
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Icon(Icons.favorite, color: zone == null ? theme.disabledColor : zoneColor(zone)),
        const SizedBox(width: 8),
        Text(bpm?.toString() ?? '--', style: theme.textTheme.displaySmall, key: const Key('live-hr')),
        const SizedBox(width: 6),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(zone == null ? 'bpm' : 'bpm · zone $zone')),
      ]),
      if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
      if (link == HrLink.needsPairing) TextButton(onPressed: () => recorder.heartRate?.pair(), child: const Text('Pair the band')),
    ]);
  }
}

/// Before Start: which band to use. Remembered between runs.
class HeartRateSetup extends StatefulWidget {
  const HeartRateSetup({super.key, required this.recorder});

  final LiveRecorder recorder;

  @override
  State<HeartRateSetup> createState() => _HeartRateSetupState();
}

class _HeartRateSetupState extends State<HeartRateSetup> {
  HrDevice? _device;
  bool _busy = false;
  String? _message;

  HeartRateLink? get link => widget.recorder.heartRate;

  @override
  void initState() {
    super.initState();
    link?.remembered().then((d) {
      if (mounted) setState(() => _device = d);
    });
  }

  Future<void> _find() async {
    final l = link!;
    setState(() {
      _busy = true;
      _message = null;
    });
    final found = await l.scan();
    if (!mounted) return;
    HrDevice? pick;
    if (found.length == 1) {
      pick = found.single;
    } else if (found.length > 1) {
      pick = await showDialog<HrDevice>(
        context: context,
        builder: (context) => SimpleDialog(title: const Text('Choose your band'), children: [
          for (final d in found) SimpleDialogOption(onPressed: () => Navigator.pop(context, d), child: Text(d.name.isEmpty ? d.id : d.name)),
        ]),
      );
    }
    if (pick != null) await l.choose(pick);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _device = pick ?? _device;
      _message = found.isEmpty
          ? 'No band found. On the Fitbit Air, turn on Share heart rate and "Always visible" in Google Health, and close other apps that may hold the connection.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (link == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.favorite_border),
        title: Text(_device == null ? 'Heart rate band' : (_device!.name.isEmpty ? _device!.id : _device!.name)),
        subtitle: Text(_message ?? (_device == null ? 'Optional. Shows live heart rate and zone.' : 'Remembered for your runs.')),
        trailing: _busy
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(onPressed: _find, child: Text(_device == null ? 'Find' : 'Change')),
      ),
    );
  }
}
