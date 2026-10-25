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
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
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
        // The bottom inset is left to the BottomAction below it.
        return SafeArea(
          bottom: false,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (left != null) ...[
                    // Timer pill, as in Google Health's workout header.
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                      decoration: ShapeDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer),
                          const SizedBox(width: 8),
                          Text(
                            _fmt(left.inSeconds + 1),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                          ),
                          IconButton(icon: const Icon(Icons.close), tooltip: 'Stop rest', onPressed: t.stop),
                        ],
                      ),
                    ),
                  ],
                  if (t.offered)
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in restChoices)
                            s == t.highlightSec
                                ? FilledButton(onPressed: () => t.start(s), child: Text(_fmt(s)))
                                : FilledButton.tonal(onPressed: () => t.start(s), child: Text(_fmt(s))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
