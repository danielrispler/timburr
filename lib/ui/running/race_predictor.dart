import 'package:flutter/material.dart';

import '../../data/best_efforts.dart';
import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/predictor.dart';
import '../../data/route_match.dart';
import '../cardio/run_page.dart';
import '../core/series_chart.dart';
import '../core/theme.dart';

/// Progress: predicted 5 km, 10 km and half marathon times from recent Best efforts, and the routes Daniel runs repeatedly. Each part is hidden until there is something to show.
class RaceSection extends StatelessWidget {
  const RaceSection({super.key, required this.store, required this.runs});

  final CardioStore store;
  final Stream<List<CardioData>> runs;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StreamBuilder<List<Effort>>(
          stream: store.watchBestEfforts(),
          builder: (context, snap) {
            final p = predictRaces(snap.data ?? const <Effort>[], DateTime.now());
            if (p.isEmpty) return const SizedBox.shrink();
            return TileGroup(title: 'Race predictions', children: [
              for (final r in p)
                ListTile(
                  dense: true,
                  title: Text(effortLabels[r.distanceM]!),
                  subtitle: Text('From your ${effortLabels[r.fromDistanceM]} on ${MaterialLocalizations.of(context).formatShortDate(r.from.toLocal())}'),
                  trailing: Text(formatDuration(r.seconds.round()), style: Theme.of(context).textTheme.titleMedium),
                ),
            ]);
          },
        ),
        StreamBuilder<List<CardioData>>(
          stream: runs,
          builder: (context, snap) {
            final groups = groupRuns(snap.data ?? const <CardioData>[]);
            if (groups.isEmpty) return const SizedBox.shrink();
            return TileGroup(title: 'Repeated routes', children: [
              for (final g in groups)
                ListTile(
                  title: Text('${g.runs.length} Runs, ${(g.runs.last.distanceKm ?? 0).toStringAsFixed(1)} km'),
                  subtitle: Text('Last on ${MaterialLocalizations.of(context).formatShortDate(g.runs.last.startedAt.toLocal())}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openRouteGroup(context, store, g.runs.last.id),
                ),
            ]);
          },
        ),
      ]);
}

/// Opens the page of the group of Runs over the same route as the Run [runId].
void openRouteGroup(BuildContext context, CardioStore store, String runId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteGroupPage(store: store, runId: runId)));

/// One group of matched Runs: a chart of Moving time on the route, and each Run, newest first.
class RouteGroupPage extends StatelessWidget {
  const RouteGroupPage({super.key, required this.store, required this.runId});

  final CardioStore store;
  final String runId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Same route')),
        body: StreamBuilder<List<CardioData>>(
          stream: store.watchAll(),
          builder: (context, snap) {
            final group = snap.data == null ? null : groupOf(groupRuns(snap.data!), runId);
            if (group == null) return const Center(child: Text('No other Runs on this route yet.'));
            final loc = MaterialLocalizations.of(context);
            final fastest = group.runs.map((r) => r.durationSec).reduce((a, b) => a < b ? a : b);
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              SeriesChart('Moving time', [for (final r in group.runs) (r.startedAt.toLocal(), r.durationSec.toDouble())], leftReserved: 52, leftLabel: (v) => formatDuration(v.round())),
              TileGroup(title: '${group.runs.length} Runs', children: [
                for (final r in group.runs.reversed)
                  ListTile(
                    dense: true,
                    title: Text('${loc.formatMediumDate(r.startedAt.toLocal())}, ${r.startedAt.toLocal().year}'),
                    subtitle: Text(r.distanceKm == null ? '' : '${r.distanceKm!.toStringAsFixed(2)} km'),
                    trailing: Text(formatDuration(r.durationSec), style: TextStyle(fontWeight: r.durationSec == fastest ? FontWeight.w700 : null)),
                    onTap: () => openRun(context, store, r.id),
                  ),
              ]),
            ]);
          },
        ),
      );
}

/// The Run page's link to the group of Runs over the same route. Hidden when the Run has no match.
class MatchedRouteTile extends StatelessWidget {
  const MatchedRouteTile({super.key, required this.store, required this.runId});

  final CardioStore store;
  final String runId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CardioData>>(
        stream: store.watchAll(),
        builder: (context, snap) {
          final group = snap.data == null ? null : groupOf(groupRuns(snap.data!), runId);
          if (group == null) return const SizedBox.shrink();
          return TileGroup(children: [
            ListTile(
              title: Text('Run on this route ${group.runs.length} times'),
              subtitle: const Text('See the trend'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openRouteGroup(context, store, runId),
            ),
          ]);
        },
      );
}
