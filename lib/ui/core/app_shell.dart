import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/sync.dart';
import '../../data/routines.dart';
import '../../data/workouts.dart';
import '../history/history_screen.dart';
import '../routines/routines_home.dart';
import '../routines/start.dart';
import '../stats/stats_screen.dart';
import '../sync/sync_ui.dart';

typedef _Tab = ({String label, IconData icon});

const _tabs = <_Tab>[
  (label: 'Home', icon: Icons.home),
  (label: 'History', icon: Icons.history),
  (label: 'Workouts', icon: Icons.fitness_center),
  (label: 'Stats', icon: Icons.insights),
];

/// Header plus bottom tabs. Each tab keeps its own navigator stack; Android back
/// pops that stack, then returns to Home, then leaves the app.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.catalog, required this.routines, required this.workouts, required this.cardio, this.sync});

  final Catalog catalog;
  final RoutineStore routines;
  final WorkoutStore workouts;
  final CardioStore cardio;
  final SyncEngine? sync; // null when no Supabase project is configured

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _keys = List.generate(_tabs.length, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    final nav = _keys[_index];
    return PopScope(
      // Nested pushes don't rebuild the shell, so decide on each back press instead of via canPop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (nav.currentState?.canPop() ?? false) {
          nav.currentState!.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_tabs[_index].label),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'More',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('More')),
                  body: MoreScreen(engine: widget.sync, catalog: widget.catalog, cardio: widget.cardio, workouts: widget.workouts),
                ),
              )),
            ),
            if (widget.sync case final sync?)
              SyncBadge(engine: sync)
            else
              const Padding(padding: EdgeInsets.only(right: 16), child: Icon(Icons.cloud_off, semanticLabel: 'Not synced')),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Navigator(
                key: _keys[i],
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _tabRoot(i)),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [for (final t in _tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
        ),
      ),
    );
  }

  late final Stores _stores =
      (routines: widget.routines, workouts: widget.workouts, cardio: widget.cardio, catalog: widget.catalog);

  Widget _tabRoot(int i) => switch (_tabs[i].label) {
        'Home' => HomeScreen(stores: _stores),
        'History' => HistoryScreen(workouts: widget.workouts, cardio: widget.cardio, catalog: widget.catalog),
        'Workouts' => WorkoutsTab(stores: _stores),
        _ => StatsScreen(stores: _stores),
      };
}
