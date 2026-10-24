import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/catalog.dart';
import '../../data/rest_timer.dart';

final _plugin = FlutterLocalNotificationsPlugin();
const _id = 12;
const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'rest_timer',
    'Rest timer',
    importance: Importance.high,
    priority: Priority.high,
    playSound: false,
    enableVibration: true,
  ),
);

RestTimer? _timer;

/// One app-wide timer so the alarm survives leaving the workout screen.
RestTimer restTimer(Catalog catalog) => _timer ??= RestTimer(
      catalog,
      schedule: (d) async {
        await _plugin.initialize(
            settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
        // Absolute instant, so UTC is fine: no local time zone lookup needed.
        await _plugin.zonedSchedule(
          id: _id,
          title: 'Rest over',
          scheduledDate: tz.TZDateTime.now(tz.UTC).add(d),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      },
      cancel: () => _plugin.cancel(id: _id),
    );

/// Non-blocking bottom bar: rest choices after a set is done, then the countdown.
class RestBar extends StatelessWidget {
  const RestBar({super.key, required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final t = restTimer(catalog);
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final left = t.remaining;
        if (!t.offered && left == null) return const SizedBox.shrink();
        return SafeArea(
          child: Material(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                if (left != null) ...[
                  const Icon(Icons.timer),
                  const SizedBox(width: 4),
                  Text(_fmt(left.inSeconds + 1), style: Theme.of(context).textTheme.titleMedium),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Stop rest', onPressed: t.stop),
                ],
                if (t.offered)
                  Expanded(
                    child: Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
                      for (final s in restChoices)
                        s == t.highlightSec
                            ? FilledButton(onPressed: () => t.start(s), child: Text(_fmt(s)))
                            : OutlinedButton(onPressed: () => t.start(s), child: Text(_fmt(s))),
                    ]),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

String _fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

