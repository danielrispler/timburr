import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/records.dart';
import '../../data/workouts.dart';
import '../core/theme.dart';
import '../exercises/exercise_picker.dart';
import '../exercises/exercise_image.dart';
import 'exercise_notes.dart';
import 'rest_bar.dart';

/// Active (or past) strength workout. Every tap writes straight to the store.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.store, required this.catalog, required this.workoutId});

  final WorkoutStore store;
  final Catalog catalog;
  final String workoutId;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final _notes = TextEditingController();
  bool _notesLoaded = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _editDate(Workout w) async {
    final d = await showDatePicker(
      context: context,
      initialDate: w.startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(w.startedAt));
    if (t == null) return;
    await widget.store.setStartedAt(widget.workoutId, DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _addExercise() async {
    final picked = await Navigator.of(context).push<List<CatalogEntry>>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Add exercises')),
          body: ExercisePicker(
            catalog: widget.catalog,
            onSelected: (e) => Navigator.of(context).pop([e]),
            onAdd: (list) => Navigator.of(context).pop(list),
          ),
        ),
      ),
    );
    for (final e in picked ?? const <CatalogEntry>[]) {
      await widget.store.addExercise(widget.workoutId, e);
    }
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard workout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.discard(widget.workoutId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    if (await widget.store.templateChanged(widget.workoutId) && mounted) {
      final update = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update saved workout?'),
          content: const Text('Save today\'s exercises and sets as the plan for next time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
          ],
        ),
      );
      if (update == true) await widget.store.updateTemplate(widget.workoutId);
    }
    await widget.store.finish(widget.workoutId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RestBar(catalog: widget.catalog),
        StreamBuilder<Workout>(
          stream: widget.store.watchWorkout(widget.workoutId),
          builder: (context, ws) => ws.data == null || ws.data!.finishedAt != null
              ? const SizedBox.shrink()
              : BottomAction(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text('Finish workout'),
                      onPressed: _finish,
                    ),
                  ],
                ),
        ),
      ],
    ),
    appBar: AppBar(
      title: StreamBuilder<Workout>(
        stream: widget.store.watchWorkout(widget.workoutId),
        builder: (context, ws) =>
            ws.data == null || ws.data!.finishedAt != null ? const Text('Workout') : _Elapsed(ws.data!.startedAt),
      ),
      actions: [IconButton(icon: const Icon(Icons.delete), tooltip: 'Discard workout', onPressed: _discard)],
    ),
    body: StreamBuilder<Workout>(
      stream: widget.store.watchWorkout(widget.workoutId),
      builder: (context, ws) {
        final w = ws.data;
        if (w == null) return const Center(child: CircularProgressIndicator());
        if (!_notesLoaded) {
          _notes.text = w.notes ?? '';
          _notesLoaded = true;
        }
        return StreamBuilder<List<WorkoutExercise>>(
          stream: widget.store.watchExercises(widget.workoutId),
          builder: (context, es) {
            final items = es.data ?? const [];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(MaterialLocalizations.of(context).formatMediumDate(w.startedAt)),
                      subtitle: Text(TimeOfDay.fromDateTime(w.startedAt).format(context)),
                      onTap: () => _editDate(w),
                    ),
                    TextField(
                      controller: _notes,
                      maxLines: null,
                      decoration: const InputDecoration(labelText: 'Workout note'),
                      onChanged: (v) => widget.store.setNotes(widget.workoutId, v.isEmpty ? null : v),
                    ),
                    RoutineNote(store: widget.store, routineId: w.routineId),
                    const SizedBox(height: 8),
                    for (final g in supersetGroups(items))
                      SupersetFrame(
                        key: ValueKey(g.first.id),
                        size: g.length,
                        child: Column(
                          children: [
                            for (final e in g)
                              _ExerciseCard(
                                key: ValueKey(e.id),
                                store: widget.store,
                                catalog: widget.catalog,
                                item: e,
                                isFirst: e == items.first,
                                isLast: e == items.last,
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add exercises'),
                      onPressed: _addExercise,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    super.key,
    required this.store,
    required this.catalog,
    required this.item,
    required this.isFirst,
    required this.isLast,
  });

  final WorkoutStore store;
  final Catalog catalog;
  final WorkoutExercise item;
  final bool isFirst, isLast;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  CatalogEntry? _entry;
  List<List<WorkoutSet>> _previous = const [];
  List<WorkoutSet> get _last => _previous.firstOrNull ?? const [];

  @override
  void initState() {
    super.initState();
    () async {
      final entry = await widget.catalog.byId(widget.item.exerciseId);
      final previous = await widget.store.previousSessions(
        widget.item.exerciseId,
        excludeWorkoutId: widget.item.workoutId,
      );
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _previous = previous;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.item, store = widget.store;
    final loadType = _entry?.loadType ?? 'weighted';
    final note = _entry?.stickyNote;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExerciseThumb(_entry),
                const SizedBox(width: 16),
                Expanded(child: Text(_entry?.name ?? '…', style: const TextStyle(fontSize: 18))),
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Move up',
                  onPressed: widget.isFirst ? null : () => store.move(e.id, -1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: 'Move down',
                  onPressed: widget.isLast ? null : () => store.move(e.id, 1),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove exercise',
                  onPressed: () => store.remove(e.id),
                ),
              ],
            ),
            ExerciseNotes(store: store, catalog: widget.catalog, item: e, stickyNote: note, isLast: widget.isLast),
            Text(
              'Last time: ${_last.isEmpty ? '—' : _last.map((s) => _describe(s, loadType)).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            StreamBuilder<List<WorkoutSet>>(
              stream: store.watchSets(e.id),
              builder: (context, snap) {
                final sets = snap.data ?? const <WorkoutSet>[];
                final prs = _entry == null ? const <String>{} : prBadges(loadType, _previous, sets);
                return Column(
                  children: [
                    for (final s in sets)
                      _SetRow(
                        key: ValueKey(s.id),
                        store: store,
                        set: s,
                        loadType: loadType,
                        pr: prs.contains(s.id),
                        onDone: () => restTimer(widget.catalog).offer(e.exerciseId),
                      ),
                  ],
                );
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
              onPressed: () => store.addSet(e.id),
            ),
          ],
        ),
      ),
    );
  }
}

String _describe(WorkoutSet s, String loadType) => switch (loadType) {
  'timed' => '${s.durationSec ?? 0}s',
  'bodyweight' => '+${_kg(s.weightKg)}×${s.reps ?? 0}',
  _ => '${_kg(s.weightKg)}×${s.reps ?? 0}',
};

String _kg(double? kg) => kg == null ? '0' : (kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toString());

class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.store,
    required this.set,
    required this.loadType,
    this.pr = false,
    required this.onDone,
  });

  final WorkoutStore store;
  final WorkoutSet set;
  final String loadType;
  final bool pr;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final s = set;
    return Row(
      children: [
        SizedBox(width: 24, child: Text('${s.setNumber}')),
        if (loadType == 'timed')
          Expanded(
            child: _Stepper(
              label: 'sec',
              value: s.durationSec,
              step: secStep,
              onChanged: (v) => store.updateSet(s.copyWith(durationSec: Value(v.round()))),
            ),
          )
        else ...[
          Expanded(
            child: _Stepper(
              label: loadType == 'bodyweight' ? '+kg' : 'kg',
              value: s.weightKg,
              step: kgStep,
              decimal: true,
              onChanged: (v) => store.updateSet(s.copyWith(weightKg: Value(v.toDouble()))),
            ),
          ),
          Expanded(
            child: _Stepper(
              label: 'reps',
              value: s.reps,
              step: repStep,
              onChanged: (v) => store.updateSet(s.copyWith(reps: Value(v.round()))),
            ),
          ),
        ],
        if (pr) const Icon(Icons.emoji_events, color: Colors.amber, semanticLabel: 'Personal record'),
        Checkbox(
          value: s.done,
          onChanged: (v) {
            store.updateSet(s.copyWith(done: v ?? false));
            if (v == true) onDone();
          },
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Delete set',
          visualDensity: VisualDensity.compact,
          onPressed: () => store.removeSet(s),
        ),
      ],
    );
  }
}

/// Large −/+ buttons around a value; tap the value to type it.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.step,
    required this.onChanged,
    this.decimal = false,
  });

  final String label;
  final num? value;
  final num step;
  final bool decimal;
  final ValueChanged<num> onChanged;

  Future<void> _type(BuildContext context) async {
    final c = TextEditingController(text: value?.toString() ?? '');
    final typed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK'))],
      ),
    );
    c.dispose();
    final v = num.tryParse(typed?.replaceAll(',', '.') ?? '');
    if (v != null) onChanged(stepped(v, 0));
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        icon: const Icon(Icons.remove),
        tooltip: '− $label',
        style: _compact,
        onPressed: () => onChanged(stepped(value, -step)),
      ),
      Flexible(
        child: InkWell(
          onTap: () => _type(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value == null ? '–' : (decimal ? _kg(value!.toDouble()) : '$value'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add),
        tooltip: '+ $label',
        style: _compact,
        onPressed: () => onChanged(stepped(value, step)),
      ),
    ],
  );
}

// Narrow phones: default 48dp buttons squeezed the value into one letter per line.
final _compact = IconButton.styleFrom(
  padding: EdgeInsets.zero,
  minimumSize: const Size(36, 48),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Live workout duration since start, ticking every second.
class _Elapsed extends StatelessWidget {
  const _Elapsed(this.start);

  final DateTime start;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: Stream.periodic(const Duration(seconds: 1)),
    builder: (context, _) {
      final d = DateTime.now().difference(start);
      final mm = (d.inMinutes % 60).toString().padLeft(2, '0'), ss = (d.inSeconds % 60).toString().padLeft(2, '0');
      return Text(
        d.isNegative ? 'Workout' : '${d.inHours}:$mm:$ss',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      );
    },
  );
}
