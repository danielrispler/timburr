import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/routines.dart';
import 'routine_editor.dart';

/// Home tab: the routines list (reads the local store, so it works offline) plus "New routine".
class RoutinesHome extends StatelessWidget {
  const RoutinesHome({super.key, required this.store, required this.catalog});

  final RoutineStore store;
  final Catalog catalog;

  void _open(BuildContext context, String id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RoutineEditor(store: store, catalog: catalog, routineId: id)));

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New routine'),
          onPressed: () async {
            final id = await store.create('New routine');
            if (context.mounted) _open(context, id);
          },
        ),
        body: StreamBuilder<List<Routine>>(
          stream: store.watchRoutines(),
          builder: (context, snap) {
            final routines = snap.data;
            if (routines == null) return const Center(child: CircularProgressIndicator());
            if (routines.isEmpty) return const Center(child: Text('No routines yet'));
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final r in routines)
                      ListTile(
                        title: Text(r.name),
                        subtitle: r.stickyNote == null || r.stickyNote!.isEmpty ? null : Text(r.stickyNote!),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _open(context, r.id),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
