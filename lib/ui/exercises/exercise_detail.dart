import 'package:flutter/material.dart';

import '../../data/catalog.dart';

class ExerciseDetail extends StatelessWidget {
  const ExerciseDetail({super.key, required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String label, String? value) => ListTile(dense: true, title: Text(label), trailing: Text(value ?? '-'));
    return Scaffold(
      appBar: AppBar(title: Text(entry.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              row('Category', entry.category),
              row('Load type', entry.loadType),
              row('Equipment', entry.equipment),
              row('Primary muscles', entry.muscles.join(', ')),
              if (entry.secondaryMuscles.isNotEmpty) row('Secondary muscles', entry.secondaryMuscles.join(', ')),
              if (entry.stickyNote != null) row('Note', entry.stickyNote),
              if (entry.instructions.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Instructions', style: text.titleMedium),
                ),
                for (final (i, step) in entry.instructions.indexed)
                  ListTile(leading: Text('${i + 1}.'), title: Text(step)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
