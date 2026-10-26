import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../exercises/exercise_detail.dart' show CustomExerciseForm;
import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/records.dart';
import '../../data/workouts.dart';
import '../core/theme.dart';
import '../routines/start.dart' show pickDateTime;
import '../exercises/exercise_picker.dart';
import '../exercises/exercise_image.dart';
import 'exercise_notes.dart';
import 'health_sheet.dart';
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
    final at = await pickDateTime(context, w.startedAt);
    if (at != null) await widget.store.setStartedAt(widget.workoutId, at);
  }

  Future<void> _addExercise() async {
    final picked = await Navigator.of(context).push<List<CatalogEntry>>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Add exercises')),
          body: ExercisePicker(
            catalog: widget.catalog,
            onSelected: (e) => Navigator.of(context).pop([e]),
            onCreate: () => Navigator.of(context)
                .push<void>(MaterialPageRoute(builder: (_) => CustomExerciseForm(catalog: widget.catalog))),
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
    // Optional Google Health stats before finish, so the one sync carries them; History can add them later.
    final w = await widget.store.watchWorkout(widget.workoutId).first;
    if (mounted) await editHealth(context, widget.store, w);
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
                // Not a ListView: it disposed off-screen cards, which rebuilt empty and resized on scroll back.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      if (w.finishedAt != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.monitor_heart),
                          title: Text(healthSummary(w) ?? 'Add Google Health stats'),
                          onTap: () => editHealth(context, widget.store, w),
                        ),
                      const SizedBox(height: 8),
                      for (final g in supersetGroups(items))
                        SupersetFrame(
                          key: ValueKey(g.first.id),
                          size: g.length,
                          child: _GroupCard(
                            store: widget.store,
                            catalog: widget.catalog,
                            items: g,
                            startedAt: w.startedAt,
                            firstId: items.first.id,
                            lastId: items.last.id,
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
              ),
            );
          },
        );
      },
    ),
  );
}

/// One exercise, or a whole superset merged into one card: each exercise's header, then the set rows
/// interleaved by round (A1, B1, A2, B2). Rest is offered only when a round ends.
class _GroupCard extends StatefulWidget {
  const _GroupCard({
    required this.store,
    required this.catalog,
    required this.items,
    required this.startedAt,
    required this.firstId,
    required this.lastId,
  });

  final WorkoutStore store;
  final Catalog catalog;
  final List<WorkoutExercise> items;
  // Previous sessions are those started before this, so reload when it changes.
  final DateTime startedAt;
  final String firstId, lastId; // of the whole workout, for the move buttons
  bool get isSuperset => items.length > 1;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  Map<String, CatalogEntry?> _entry = {};
  Map<String, List<List<WorkoutSet>>> _previous = {};
  // Kept per card so a rebuild does not resubscribe (and briefly empty) the inner streams.
  final _sets = <String, Stream<List<WorkoutSet>>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_GroupCard old) {
    super.didUpdateWidget(old);
    String ids(_GroupCard c) => c.items.map((e) => e.exerciseId).join();
    if (old.startedAt != widget.startedAt || ids(old) != ids(widget)) _load();
  }

  void _load() {
    () async {
      final entry = <String, CatalogEntry?>{}, previous = <String, List<List<WorkoutSet>>>{};
      for (final e in widget.items) {
        entry[e.exerciseId] = await widget.catalog.byId(e.exerciseId);
        previous[e.exerciseId] = await widget.store.previousSessions(e.exerciseId, excludeWorkoutId: e.workoutId);
      }
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _previous = previous;
      });
    }();
  }

  String _loadType(WorkoutExercise e) => _entry[e.exerciseId]?.loadType ?? 'weighted';

  Future<void> _confirmRemove(WorkoutExercise e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${_entry[e.exerciseId]?.name ?? 'exercise'}?'),
        content: const Text('Its sets in this workout are removed too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await widget.store.remove(e.id);
  }

  Widget _header(int i, WorkoutExercise e) {
    final store = widget.store, entry = _entry[e.exerciseId];
    final last = _previous[e.exerciseId]?.firstOrNull ?? const [];
    return Padding(
      padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.isSuperset) ...[_Tag(i), const SizedBox(width: 8)],
              ExerciseThumb(entry),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry?.name ?? '…',
                  style: const TextStyle(fontSize: 17),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (e.backupExerciseId != null)
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Swap to backup exercise',
                  onPressed: () => store.swap(e),
                ),
              // One menu instead of three icons, so long names keep their width.
              PopupMenuButton<VoidCallback>(
                tooltip: 'Exercise options',
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: e.id != widget.firstId,
                    value: () => store.move(e.id, -1),
                    child: const ListTile(leading: Icon(Icons.arrow_upward), title: Text('Move up')),
                  ),
                  PopupMenuItem(
                    enabled: e.id != widget.lastId,
                    value: () => store.move(e.id, 1),
                    child: const ListTile(leading: Icon(Icons.arrow_downward), title: Text('Move down')),
                  ),
                  PopupMenuItem(
                    value: () => _confirmRemove(e),
                    child: const ListTile(leading: Icon(Icons.close), title: Text('Remove')),
                  ),
                ],
              ),
            ],
          ),
          ExerciseNotes(
            key: ValueKey('${e.id}-${e.exerciseId}'), // a swap brings the other exercise's sticky note
            store: store,
            catalog: widget.catalog,
            item: e,
            stickyNote: entry?.stickyNote,
            isLast: e.id == widget.lastId,
          ),
          Text(
            'Last time: ${last.isEmpty ? '—' : last.map((s) => _describe(s, _loadType(e))).join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Every exercise's live sets, one nested stream per exercise.
  Widget _withSets(Widget Function(List<List<WorkoutSet>>) build, [List<List<WorkoutSet>> acc = const []]) {
    if (acc.length == widget.items.length) return build(acc);
    return StreamBuilder<List<WorkoutSet>>(
      stream: _sets.putIfAbsent(widget.items[acc.length].id, () => widget.store.watchSets(widget.items[acc.length].id)),
      builder: (context, snap) => _withSets(build, [...acc, snap.data ?? const []]),
    );
  }

  Widget _rows(List<List<WorkoutSet>> perExercise) {
    final items = widget.items, store = widget.store;
    final rows = supersetRows(perExercise);
    final prs = {
      for (final (i, e) in items.indexed)
        if (_entry[e.exerciseId] != null)
          ...prBadges(_loadType(e), _previous[e.exerciseId] ?? const [], perExercise[i]),
    };
    final next = rows.indexWhere((r) => !r.set.done); // the row to do now, highlighted
    final label = Theme.of(context).textTheme.labelSmall;
    final first = _loadType(items.first);
    // Mixed load types (timed with weighted) have no shared units, so no header.
    final sameUnits = items.every((e) => _loadType(e) == first);
    final ordinal = List.filled(items.length, 0);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          // One header instead of a unit label under every value.
          if (rows.isNotEmpty && sameUnits)
            Row(
              children: [
                SizedBox(width: 32, child: Text('Set', style: label)),
                if (first == 'timed')
                  Expanded(
                    child: Center(child: Text('sec', style: label)),
                  )
                else ...[
                  Expanded(
                    child: Center(child: Text(first == 'bodyweight' ? '+kg' : 'kg', style: label)),
                  ),
                  Expanded(
                    child: Center(child: Text('reps', style: label)),
                  ),
                ],
                const SizedBox(width: 48),
              ],
            ),
          for (final (k, r) in rows.indexed)
            _SetRow(
              key: ValueKey(r.set.id),
              store: store,
              set: r.set,
              label: r.set.isDrop ? 'D' : '${widget.isSuperset ? _letter(r.exercise) : ''}${ordinal[r.exercise] += 1}',
              tag: widget.isSuperset ? r.exercise : null,
              loadType: _loadType(items[r.exercise]),
              pr: prs.contains(r.set.id),
              current: k == next,
              // A drop chain grows from its last row only.
              onDrop:
                  r.set.done && !(k + 1 < rows.length && rows[k + 1].set.isDrop && rows[k + 1].exercise == r.exercise)
                  ? () {
                      restTimer(widget.catalog).dismiss();
                      store.addDrop(r.set);
                    }
                  : null,
              onDone: r.endsRound ? () => restTimer(widget.catalog).offer(items[r.exercise].exerciseId) : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, e) in widget.items.indexed) _header(i, e),
          _withSets(_rows),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(widget.isSuperset ? 'Add round' : 'Add set'),
            onPressed: () async {
              for (final e in widget.items) {
                await widget.store.addSet(e.id);
              }
            },
          ),
        ],
      ),
    ),
  );
}

String _letter(int i) => String.fromCharCode(65 + i);

/// Colours for superset exercises A, B, C…
Color _tagColor(BuildContext context, int i) {
  final c = Theme.of(context).colorScheme;
  return [c.primary, c.tertiary, c.secondary][i % 3];
}

/// Letter badge of a superset exercise.
class _Tag extends StatelessWidget {
  const _Tag(this.i);

  final int i;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 12,
    backgroundColor: _tagColor(context, i),
    child: Text(_letter(i), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.surface)),
  );
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
    required this.label,
    this.tag,
    required this.loadType,
    this.pr = false,
    this.current = false,
    this.onDrop,
    this.onDone,
  });

  final WorkoutStore store;
  final WorkoutSet set;
  final String label;
  final int? tag; // superset exercise index, colours the label
  final String loadType;
  final bool pr, current;
  final VoidCallback? onDrop, onDone; // onDone null: no rest offered here (mid-round)

  @override
  Widget build(BuildContext context) {
    final s = set;
    // Swipe left to delete; no per-row delete button.
    return Dismissible(
      key: ValueKey('dismiss-${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        await store.removeSet(s);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Set ${s.setNumber} deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                // removeSet shifted later sets down by one; shift them back, then undelete.
                for (final x in await store.watchSets(s.workoutExerciseId).first) {
                  if (x.setNumber >= s.setNumber) await store.patchSet(x.id, setNumber: x.setNumber + 1);
                }
                await store.patchSet(s.id, deletedAt: const Value(null));
              },
            ),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(left: s.isDrop ? 12 : 0),
        decoration: BoxDecoration(
          color: current ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                label,
                style: TextStyle(
                  color: tag == null ? null : _tagColor(context, tag!),
                  fontWeight: tag == null ? null : FontWeight.w600,
                ),
              ),
            ),
            if (loadType == 'timed')
              Expanded(
                child: _Stepper(
                  label: 'sec',
                  value: s.durationSec,
                  step: secStep,
                  onChanged: (v) => store.patchSet(s.id, durationSec: Value(v.round())),
                  onStep: (d) => store.stepSet(s.id, SetField.durationSec, d),
                ),
              )
            else ...[
              Expanded(
                child: _Stepper(
                  label: loadType == 'bodyweight' ? '+kg' : 'kg',
                  value: s.weightKg,
                  step: kgStep,
                  decimal: true,
                  onChanged: (v) => store.patchSet(s.id, weightKg: Value(v.toDouble())),
                  onStep: (d) => store.stepSet(s.id, SetField.weightKg, d),
                ),
              ),
              Expanded(
                child: _Stepper(
                  label: 'reps',
                  value: s.reps,
                  step: repStep,
                  onChanged: (v) => store.patchSet(s.id, reps: Value(v.round())),
                  onStep: (d) => store.stepSet(s.id, SetField.reps, d),
                ),
              ),
            ],
            if (pr) const Icon(Icons.emoji_events, color: Colors.amber, semanticLabel: 'Personal record'),
            if (onDrop != null)
              IconButton(
                icon: const Icon(Icons.trending_down),
                tooltip: 'Add drop set',
                style: _compact,
                onPressed: onDrop,
              ),
            Checkbox(
              value: s.done,
              onChanged: (v) {
                store.patchSet(s.id, done: v ?? false);
                if (v == true) onDone?.call();
              },
            ),
          ],
        ),
      ),
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
    required this.onStep,
    this.decimal = false,
  });

  final String label;
  final num? value;
  final num step;
  final bool decimal;
  final ValueChanged<num> onChanged;
  // +/- add to the stored value, so taps faster than the rebuild still count.
  final ValueChanged<num> onStep;

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
    // Same bounds as PlannedSetsEditor; weight_kg is numeric(6,2) on the server.
    if (v != null && v >= 0 && v <= 9999) onChanged(stepped(v, 0));
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        icon: const Icon(Icons.remove),
        tooltip: '− $label',
        style: _compact,
        onPressed: () => onStep(-step),
      ),
      Flexible(
        child: InkWell(
          onTap: () => _type(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              value == null ? '–' : (decimal ? _kg(value!.toDouble()) : '$value'),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add),
        tooltip: '+ $label',
        style: _compact,
        onPressed: () => onStep(step),
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
