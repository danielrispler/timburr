import 'package:flutter/material.dart';

import 'data/catalog.dart';
import 'data/db.dart';
import 'data/routines.dart';
import 'ui/core/app_shell.dart';

void main() {
  final db = AppDb();
  runApp(TimburrApp(catalog: Catalog(db), routines: RoutineStore(db)));
}

class TimburrApp extends StatelessWidget {
  const TimburrApp({super.key, required this.catalog, required this.routines});

  final Catalog catalog;
  final RoutineStore routines;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, brightness: Brightness.dark),
      ),
      home: AppShell(catalog: catalog, routines: routines),
    );
  }
}
