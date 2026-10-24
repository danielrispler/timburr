import 'package:flutter/material.dart';

import 'data/catalog.dart';
import 'data/db.dart';
import 'ui/core/app_shell.dart';

void main() => runApp(TimburrApp(catalog: Catalog(AppDb())));

class TimburrApp extends StatelessWidget {
  const TimburrApp({super.key, required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, brightness: Brightness.dark),
      ),
      home: AppShell(catalog: catalog),
    );
  }
}
