import 'package:flutter/material.dart';

import 'ui/core/app_shell.dart';

void main() => runApp(const TimburrApp());

class TimburrApp extends StatelessWidget {
  const TimburrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timburr',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, brightness: Brightness.dark),
      ),
      home: const AppShell(),
    );
  }
}
