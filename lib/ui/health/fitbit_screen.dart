import 'package:flutter/material.dart';

import '../../data/error_log.dart';
import '../../data/health_connect.dart';
import '../core/theme.dart';

/// "Check Fitbit now": reads Health Connect and says what it filled in.
Future<void> checkFitbitNow(BuildContext context, HealthConnect health) async {
  final messenger = ScaffoldMessenger.of(context);
  String text;
  try {
    final r = await health.check();
    text = r == null
        ? 'Fitbit is not connected'
        : r.runs == 0
            ? 'Nothing new from the Fitbit'
            : 'Filled in ${r.runs} ${r.runs == 1 ? 'Run' : 'Runs'} from the Fitbit';
  } catch (e, st) {
    reportError('health_connect', e, st, {'call': 'sessions'});
    text = 'Could not read Health Connect: $e';
  }
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// The More row for the Fitbit connection.
class FitbitTile extends StatelessWidget {
  const FitbitTile({super.key, required this.health});

  final HealthConnect health;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: health.status,
        builder: (context, status, _) => ListTile(
          leading: const IconTile(Icons.watch),
          title: const Text('Fitbit (Health Connect)'),
          subtitle: Text(status == HcStatus.connected ? 'Connected' : 'Not connected'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FitbitScreen(health: health))),
        ),
      );
}

/// Connects, checks and disconnects Health Connect. The explanation comes before the system prompt, which only Connect opens.
class FitbitScreen extends StatefulWidget {
  const FitbitScreen({super.key, required this.health});

  final HealthConnect health;

  @override
  State<FitbitScreen> createState() => _FitbitScreenState();
}

class _FitbitScreenState extends State<FitbitScreen> {
  bool _busy = false;

  HealthConnect get health => widget.health;

  @override
  void initState() {
    super.initState();
    health.refresh();
  }

  Future<void> _do(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _do(() async {
        if (await health.connect() == HcStatus.connected && mounted) await checkFitbitNow(context, health);
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fitbit')),
        body: ValueListenableBuilder(
          valueListenable: health.status,
          builder: (context, status, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Timburr can read your Fitbit\'s exercise sessions from Health Connect: their times, heart rate, distance and calories.\n\n'
                'They only fill in what is missing on Runs you recorded or imported, matched by time. A Fitbit session that matches no Run is ignored, '
                'so Runs are only ever created by you. Values you typed are never replaced.\n\n'
                'Timburr never writes to Health Connect. It checks when the app opens or comes back, and when you tap Check Fitbit now.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ...switch (status) {
                HcStatus.unknown => [const Center(child: CircularProgressIndicator())],
                HcStatus.unavailable => [const Text('Health Connect is not available on this phone.')],
                HcStatus.updateNeeded => [const Text('Health Connect needs an update from the Play Store first.')],
                HcStatus.disconnected => [
                    FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
                    const SizedBox(height: 8),
                    Text('Android then asks which data Timburr may read.', style: Theme.of(context).textTheme.bodySmall),
                  ],
                HcStatus.connected => [
                    FilledButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('Check Fitbit now'),
                      onPressed: _busy ? null : () => _do(() => checkFitbitNow(context, health)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _busy ? null : () => _do(health.disconnect), child: const Text('Disconnect')),
                  ],
              },
            ],
          ),
        ),
      );
}
