import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/routines.dart';
import '../core/theme.dart';
import '../exercises/exercise_picker.dart';

/// Name, sticky note and ordered exercise list of one routine. Fields save on change.
class RoutineEditor extends StatefulWidget {
  const RoutineEditor({super.key, required this.store, required this.catalog, required this.routineId});

  final RoutineStore store;
  final Catalog catalog;
  final String routineId;

  @override
  State<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditor> {
  final _name = TextEditingController(), _note = TextEditingController();
  Map<String, CatalogEntry> _entries = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.store.watchRoutines().first.then((rs) {
      final r = rs.where((r) => r.id == widget.routineId).firstOrNull;
      if (r == null || !mounted) return;
      setState(() {
        _name.text = r.name;
        _note.text = r.stickyNote ?? '';
        _loaded = true;
      });
    });
    _loadNames();
  }

  Future<void> _loadNames() async {
    final all = await widget.catalog.list();
    if (mounted) {
      setState(() => _entries = {for (final e in all) if (e.rowId != null) e.rowId!: e});
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _saveFields() {
    final name = _name.text.trim();
    widget.store.update(widget.routineId,
        name: name.isEmpty ? 'Untitled' : name, stickyNote: _note.text.isEmpty ? null : _note.text);
  }

  Future<void> _addExercise() async {
    final entry = await Navigator.of(context).push<CatalogEntry>(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Add exercise')),
        body: ExercisePicker(catalog: widget.catalog, onSelected: (e) => Navigator.of(context).pop(e)),
      ),
    ));
    if (entry == null) return;
    await widget.store.add(widget.routineId, entry);
    await _loadNames();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete routine?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(widget.routineId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Routine'),
          actions: [IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete routine', onPressed: _delete)],
        ),
        bottomNavigationBar: BottomAction(children: [
          FilledButton.tonalIcon(icon: const Icon(Icons.add), label: const Text('Add exercises'), onPressed: _addExercise),
        ]),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: StreamBuilder<List<RoutineExercise>>(
                    stream: widget.store.watchExercises(widget.routineId),
                    builder: (context, snap) {
                      final items = snap.data ?? const [];
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        children: [
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Name'),
                            onChanged: (_) => _saveFields(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _note,
                            maxLines: null,
                            decoration: const InputDecoration(labelText: 'Sticky note'),
                            onChanged: (_) => _saveFields(),
                          ),
                          const SizedBox(height: 12),
                          if (items.isNotEmpty)
                            TileGroup(title: 'Exercises', children: [
                          for (final (i, e) in items.indexed)
                            ListTile(
                              leading: IconTile(muscleIcon(_entries[e.exerciseId]?.muscles.firstOrNull)),
                              title: Text(_entries[e.exerciseId]?.name ?? '…'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                    icon: const Icon(Icons.arrow_upward),
                                    tooltip: 'Move up',
                                    onPressed: i == 0 ? null : () => widget.store.move(e.id, -1)),
                                IconButton(
                                    icon: const Icon(Icons.arrow_downward),
                                    tooltip: 'Move down',
                                    onPressed: i == items.length - 1 ? null : () => widget.store.move(e.id, 1)),
                                IconButton(
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Remove',
                                    onPressed: () => widget.store.remove(e.id)),
                              ]),
                            ),
                            ]),
                        ],
                      );
                    },
                  ),
                ),
              ),
      );
}
