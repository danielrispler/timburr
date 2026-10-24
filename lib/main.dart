import 'package:flutter/material.dart';

import 'data/catalog.dart';
import 'data/db.dart';
import 'data/routines.dart';
import 'data/workouts.dart';
import 'ui/core/app_shell.dart';

void main() {
  final db = AppDb();
  // TODO(#8): finishing a workout triggers sync. Wire it here: onFinished: sync.
  final workouts = WorkoutStore(db, onFinished: null);
  runApp(TimburrApp(catalog: Catalog(db), routines: RoutineStore(db), workouts: workouts));
}

class TimburrApp extends StatelessWidget {
  const TimburrApp({super.key, required this.catalog, required this.routines, required this.workouts});

  final Catalog catalog;
  final RoutineStore routines;
  final WorkoutStore workouts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, brightness: Brightness.dark),
      ),
      home: AppShell(catalog: catalog, routines: routines, workouts: workouts),
    );
  }
}
