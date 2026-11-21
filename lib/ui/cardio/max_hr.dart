import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/hr_zones.dart';
import '../../data/settings.dart';
import '../../data/track.dart';
import '../core/theme.dart';

/// The Max HR row under More: shows the value in force, opens [showMaxHrDialog].
class MaxHrTile extends StatelessWidget {
  const MaxHrTile({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) => StreamBuilder<AppSetting?>(
        stream: settings.watch(),
        builder: (context, snap) {
          final s = snap.data;
          final unset = s?.maxHr == null && s?.birthYear == null;
          final value = effectiveMaxHr(s?.maxHr, s?.birthYear, DateTime.now());
          return ListTile(
            leading: const IconTile(Icons.favorite),
            title: const Text('Max HR'),
            subtitle: Text(unset ? '$value bpm (default, tap to set)' : '$value bpm'),
            onTap: () => showMaxHrDialog(context, settings, s),
          );
        },
      );
}

/// Sets Max HR directly or from a birth year (220 minus age). With nothing set yet it leads with the birth year.
Future<void> showMaxHrDialog(BuildContext context, SettingsStore settings, AppSetting? current) {
  final unset = current?.maxHr == null && current?.birthYear == null;
  final maxHr = TextEditingController(text: current?.maxHr?.toString() ?? '');
  final year = TextEditingController(text: current?.birthYear?.toString() ?? '');
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Max HR'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (unset) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Zones use $defaultMaxHr until you set this. Enter your birth year to use 220 minus your age.')),
        TextField(controller: year, keyboardType: TextInputType.number, autofocus: unset, decoration: const InputDecoration(labelText: 'Birth year')),
        const SizedBox(height: 8),
        TextField(controller: maxHr, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Max HR (bpm, $minMaxHr-$maxMaxHr)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final y = int.tryParse(year.text.trim()), m = int.tryParse(maxHr.text.trim());
            // An edited Max HR wins; otherwise a birth year recomputes it.
            if (m != null && m != current?.maxHr && m >= minMaxHr && m <= maxMaxHr) {
              await settings.setMaxHr(m);
            } else if (y != null && y > 1900 && y <= DateTime.now().year) {
              await settings.setBirthYear(y);
            } else {
              return;
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

const zoneColors = [Color(0xFF90A4AE), Color(0xFF4FC3F7), Color(0xFF66BB6A), Color(0xFFFFB74D), Color(0xFFE57373)];

/// Time in each HR zone as a bar with a percentage per zone. Hidden for a Run without heart rate.
class ZoneBar extends StatelessWidget {
  const ZoneBar({super.key, required this.track, required this.settings});

  final Track? track;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) => StreamBuilder<AppSetting?>(
        stream: settings.watch(),
        builder: (context, snap) {
          final t = track;
          if (t == null) return const SizedBox();
          final max = effectiveMaxHr(snap.data?.maxHr, snap.data?.birthYear, DateTime.now());
          final pct = zonePercents(zoneSeconds(t, max));
          if (pct == null) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Heart rate zones', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(children: [
                  for (var z = 0; z < 5; z++)
                    if (pct[z] > 0) Expanded(flex: pct[z], child: Container(height: 14, color: zoneColors[z])),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                for (var z = 0; z < 5; z++)
                  Expanded(
                    child: Column(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: zoneColors[z], shape: BoxShape.circle)),
                      Text('Z${z + 1}', style: Theme.of(context).textTheme.bodySmall),
                      Text('${pct[z]}%', style: Theme.of(context).textTheme.titleSmall),
                    ]),
                  ),
              ]),
              Text('of Max HR $max bpm', style: Theme.of(context).textTheme.bodySmall),
            ]),
          );
        },
      );
}
