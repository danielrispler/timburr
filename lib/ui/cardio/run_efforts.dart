import 'package:flutter/material.dart';

import '../../data/best_efforts.dart';
import '../../data/cardio.dart';
import '../core/theme.dart';

/// The small "PR" mark on a fastest-ever effort.
class PrBadge extends StatelessWidget {
  const PrBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
      child: Text('PR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer)),
    );
  }
}

/// The Run page's Best efforts section: this Run's fastest time at each distance it covers, with a PR badge on the ones that are the fastest ever. Hidden when it has none.
class RunBestEfforts extends StatelessWidget {
  const RunBestEfforts({super.key, required this.store, required this.runId});

  final CardioStore store;
  final String runId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Effort>>(
        stream: store.watchBestEfforts(),
        builder: (context, snap) {
          final all = snap.data ?? const <Effort>[];
          final mine = [for (final e in all) if (e.cardioId == runId) e]..sort((a, b) => a.distanceM.compareTo(b.distanceM));
          if (mine.isEmpty) return const SizedBox.shrink();
          return TileGroup(title: 'Best efforts', children: [
            for (final e in mine)
              ListTile(
                dense: true,
                title: Text(effortLabels[e.distanceM]!),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (prAt(all, e.distanceM)?.cardioId == runId) const Padding(padding: EdgeInsets.only(right: 8), child: PrBadge()),
                  Text(formatDuration(e.seconds.round())),
                ]),
              ),
          ]);
        },
      );
}
