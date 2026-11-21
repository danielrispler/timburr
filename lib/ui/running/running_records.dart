import 'package:flutter/material.dart';

import '../../data/best_efforts.dart';
import '../../data/cardio.dart';
import '../../data/db.dart';
import '../cardio/run_efforts.dart';
import '../cardio/run_page.dart';
import '../core/theme.dart';
import '../routines/start.dart';

/// Running > Records: the PR at each distance, the longest Run, and the top few efforts per distance. Each row opens its Run.
class RunningRecords extends StatelessWidget {
  const RunningRecords({super.key, required this.stores, required this.runs});

  final Stores stores;
  final Stream<List<CardioData>> runs;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CardioData>>(
        stream: runs,
        builder: (context, runSnap) => StreamBuilder<List<Effort>>(
          stream: stores.cardio.watchBestEfforts(),
          builder: (context, snap) {
            final all = snap.data, runs = runSnap.data;
            if (all == null || runs == null) return const Center(child: CircularProgressIndicator());
            final loc = MaterialLocalizations.of(context);
            final longest = runs.where((r) => r.distanceKm != null).fold<CardioData?>(null, (a, b) => a == null || b.distanceKm! > a.distanceKm! ? b : a);
            final prs = [for (final d in effortDistances.keys) ?prAt(all, d)];
            if (prs.isEmpty && longest == null) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Records appear after your first outdoor Runs with a track.', textAlign: TextAlign.center)));
            }
            Widget row(String title, String value, DateTime at, String id, {bool pr = false}) => ListTile(
                  title: Text(title),
                  subtitle: Text(loc.formatMediumDate(at.toLocal())),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (pr) const Padding(padding: EdgeInsets.only(right: 8), child: PrBadge()),
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  onTap: () => openRun(context, stores.cardio, id),
                );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                  TileGroup(title: 'Personal records', children: [
                    for (final e in prs) row(effortLabels[e.distanceM]!, formatDuration(e.seconds.round()), e.startedAt, e.cardioId),
                    if (longest != null) row('Longest Run', '${longest.distanceKm!.toStringAsFixed(1)} km', longest.startedAt, longest.id),
                  ]),
                  for (final d in effortDistances.keys)
                    if (topEfforts(all, d) case final top when top.isNotEmpty)
                      TileGroup(title: 'Top ${effortLabels[d]}', children: [
                        for (var i = 0; i < top.length; i++) row('${i + 1}. ${formatDuration(top[i].seconds.round())}', '', top[i].startedAt, top[i].cardioId, pr: i == 0),
                      ]),
                ]),
              ),
            );
          },
        ),
      );
}
