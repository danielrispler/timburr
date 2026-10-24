import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/sync.dart';
import '../exercises/exercise_detail.dart';
import '../exercises/exercise_picker.dart';
import '../../data/routines.dart';
import '../../data/workouts.dart';
import '../history/history_screen.dart';
import '../routines/routines_home.dart';
import '../sync/sync_ui.dart';

typedef _Tab = ({String label, IconData icon});

const _tabs = <_Tab>[
  (label: 'Home', icon: Icons.home),
  (label: 'History', icon: Icons.history),
  (label: 'Exercises', icon: Icons.fitness_center),
  (label: 'More', icon: Icons.more_horiz),
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

  Widget _tabRoot(int i) => _tabs[i].label == 'Exercises'
      ? Builder(
          builder: (context) => ExercisePicker(
            catalog: widget.catalog,
            onSelected: (e) => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => ExerciseDetail(catalog: widget.catalog, entry: e, workouts: widget.workouts))),
            onCreate: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => CustomExerciseForm(catalog: widget.catalog))),
          ),
        )
      : i == 0
          ? RoutinesHome(store: widget.routines, catalog: widget.catalog, workouts: widget.workouts, cardio: widget.cardio)
          : _tabs[i].label == 'History'
              ? HistoryScreen(workouts: widget.workouts, cardio: widget.cardio, catalog: widget.catalog)
          : _tabs[i].label == 'More'
              ? MoreScreen(engine: widget.sync, catalog: widget.catalog)
          : _Placeholder(_tabs[i].label);
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(child: Text(label));
}
