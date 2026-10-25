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
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // A custom last rest gets its own chip next to the presets.
                          for (final s in [
                            ...restChoices,
                            if (t.highlightSec case final h? when !restChoices.contains(h)) h,
                          ])
                            s == t.highlightSec
                                ? FilledButton(onPressed: () => t.start(s), child: Text(_fmt(s)))
                                : FilledButton.tonal(onPressed: () => t.start(s), child: Text(_fmt(s))),
                          OutlinedButton(onPressed: () => _custom(context, t), child: const Text('Custom')),
                          IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: t.dismiss),
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

/// Minutes and seconds typed in a dialog, then started.
Future<void> _custom(BuildContext context, RestTimer t) async {
  t.dismiss();
  final m = TextEditingController(), sec = TextEditingController();
  Widget field(TextEditingController c, String label) => Expanded(
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    ),
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Custom rest'),
      content: Row(children: [field(m, 'min'), const SizedBox(width: 16), field(sec, 'sec')]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
      ],
    ),
  );
  final total = (int.tryParse(m.text) ?? 0) * 60 + (int.tryParse(sec.text) ?? 0);
  m.dispose();
  sec.dispose();
  if (ok == true && total > 0 && total <= 3600) await t.start(total);
}

String _fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
