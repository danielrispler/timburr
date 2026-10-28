import 'package:flutter/material.dart';

import '../exercises/exercise_detail.dart' show CustomExerciseForm;
import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/routines.dart';
import '../core/theme.dart';
import '../exercises/exercise_image.dart';
import '../exercises/exercise_picker.dart';
import 'planned_sets.dart';
import 'start.dart';

// Shorter than the theme's 52dp buttons, so more of the exercise list fits.
const _short = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 40)), tapTargetSize: MaterialTapTargetSize.shrinkWrap);

/// Builder for one saved workout, as in Google Health: exercises with planned sets, start or log it.
/// A [isNew] workout that is never named with the bookmark is deleted on leaving, but can still be started.
class RoutineEditor extends StatefulWidget {
  const RoutineEditor({super.key, required this.stores, required this.routineId, this.isNew = false});

  final Stores stores;
  final String routineId;
  final bool isNew;

  @override
  State<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditor> {
  late final _store = widget.stores.routines;
  final _note = TextEditingController();
  Routine? _routine;
  Map<String, CatalogEntry> _entries = {};
  late bool _saved = !widget.isNew;
  final _dismissed = <String>{}; // hidden at once; Dismissible must leave the tree before the DB write lands

  @override
  void initState() {
    super.initState();
    _loadRoutine();
    _loadNames();
  }

  Future<void> _loadRoutine() async {
    final r = (await _store.watchRoutines().first).where((r) => r.id == widget.routineId).firstOrNull;
    if (r == null || !mounted) return;
    setState(() {
      _routine = r;
      _note.text = r.stickyNote ?? '';
    });
  }

  Future<void> _loadNames() async {
    final catalog = widget.stores.catalog;
    final entries = {for (final e in await catalog.list()) if (e.rowId != null) e.rowId!: e};
    // list() skips deleted exercises; the routine may still reference some.
    for (final e in await _store.watchExercises(widget.routineId).first) {
      for (final id in [e.exerciseId, ?e.backupExerciseId]) {
        if (!entries.containsKey(id)) {
          final d = await catalog.byId(id);
          if (d != null) entries[id] = d;
        }
      }
    }
    if (mounted) setState(() => _entries = entries);
  }

  @override
  void dispose() {
    if (!_saved) _store.delete(widget.routineId);
    _note.dispose();
    super.dispose();
  }

  void _saveNote() => _store.update(widget.routineId,
      name: _routine!.name, stickyNote: _note.text.isEmpty ? null : _note.text);

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _saved ? _routine!.name : '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your workout'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Workout name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    await _store.update(widget.routineId, name: name, stickyNote: _note.text.isEmpty ? null : _note.text);
    _saved = true;
    await _loadRoutine();
  }

  Future<void> _addExercises() async {
    final picked = await Navigator.of(context).push<List<CatalogEntry>>(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Add exercises')),
        body: ExercisePicker(
          catalog: widget.stores.catalog,
          onSelected: (e) => Navigator.of(context).pop([e]),
          onCreate: () => Navigator.of(context)
              .push<void>(MaterialPageRoute(builder: (_) => CustomExerciseForm(catalog: widget.stores.catalog))),
          onAdd: (list) => Navigator.of(context).pop(list),
        ),
      ),
    ));
    for (final e in picked ?? const <CatalogEntry>[]) {
      await _store.add(widget.routineId, e);
    }
    await _loadNames();
  }

  /// Picks the slot's backup exercise, swapped in during a workout; "No backup" clears it.
  Future<void> _pickBackup(RoutineExercise e) async {
    final picked = await Navigator.of(context).push<(CatalogEntry?,)>(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Backup exercise'), actions: [
          if (e.backupExerciseId != null)
            TextButton(onPressed: () => Navigator.of(context).pop((null,)), child: const Text('No backup')),
        ]),
        body: ExercisePicker(
          catalog: widget.stores.catalog,
          onSelected: (x) => Navigator.of(context).pop((x,)),
          onAdd: (list) => Navigator.of(context).pop((list.first,)),
        ),
      ),
    ));
    if (picked == null) return;
    await _store.setBackup(e.id, picked.$1);
    await _loadNames();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    _saved = false; // dispose deletes it
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = _routine;
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null || !_saved ? 'New workout' : r.name),
        actions: [
          IconButton(icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border), tooltip: 'Save and name', onPressed: r == null ? null : _rename),
          IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete workout', onPressed: _delete),
        ],
      ),
      bottomNavigationBar: BottomAction(children: [
        FilledButton.icon(
          style: _short,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start workout'),
          onPressed: () => startStrength(context, widget.stores, routineId: widget.routineId, now: true),
        ),
        TextButton.icon(
          style: _short,
          icon: const Icon(Icons.check),
          label: const Text('I have done this workout'),
          onPressed: () => startStrength(context, widget.stores, routineId: widget.routineId, now: false),
        ),
      ]),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: StreamBuilder<List<RoutineExercise>>(
                  stream: _store.watchExercises(widget.routineId),
                  builder: (context, snap) {
                    final items = [for (final e in snap.data ?? const <RoutineExercise>[]) if (!_dismissed.contains(e.id)) e];
                    final equipment = {for (final e in items) ?_entries[e.exerciseId]?.equipment};
                    return ReorderableListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (equipment.isNotEmpty)
                          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(equipment.join(' • '))),
                        TextField(
                          controller: _note,
                          maxLines: null,
                          decoration: const InputDecoration(
                              labelText: 'Sticky note',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          onChanged: (_) => _saveNote(),
                        ),
                        const SizedBox(height: 12),
                        if (items.isEmpty) const ListTile(title: Text('No exercises yet')),
                      ]),
                      // With the list, as on the workout screen, so the bottom bar keeps only the start actions.
                      footer: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.add), label: const Text('Add exercises'), onPressed: _addExercises),
                      ),
                      onReorderItem: (from, to) => _store.reorder(items[from].id, to),
                      children: [
                        for (final e in items)
                          Dismissible(
                            key: ValueKey(e.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              color: Theme.of(context).colorScheme.errorContainer,
                              child: const Icon(Icons.delete),
                            ),
                            onDismissed: (_) {
                              setState(() => _dismissed.add(e.id));
                              _store.remove(e.id);
                            },
                            child: Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: StreamBuilder<List<RoutineSet>>(
                                stream: _store.watchSets(e.id),
                                builder: (context, sets) => ListTile(
                                  leading: ExerciseThumb(_entries[e.exerciseId]),
                                  title: Text(_entries[e.exerciseId]?.name ?? '…'),
                                  subtitle: Text([
                                    planSummary(sets.data ?? const []),
                                    if (e.backupExerciseId != null) 'or ${_entries[e.backupExerciseId]?.name ?? '…'}',
                                  ].join('\n')),
                                  trailing: IconButton(
                                    icon: Icon(e.backupExerciseId == null ? Icons.swap_horiz : Icons.swap_horizontal_circle),
                                    tooltip: 'Backup exercise',
                                    onPressed: () => _pickBackup(e),
                                  ),
                                  onTap: _entries[e.exerciseId] == null
                                      ? null
                                      : () => Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => PlannedSetsEditor(
                                              store: _store, entry: _entries[e.exerciseId]!, routineExerciseId: e.id))),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }
}
