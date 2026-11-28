import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/interval_store.dart';
import '../../data/intervals.dart';
import '../../data/run_analysis.dart' show stepAvgHr;
import '../../data/track.dart';
import '../cardio/run_page.dart';
import '../core/series_chart.dart';
import '../core/theme.dart';

/// The setup screen's choice of plan: each saved plan (with Edit, History and Delete), Free, and New plan. [selected] null is Free.
class PlanPicker extends StatelessWidget {
  const PlanPicker({super.key, required this.store, required this.selected, required this.onSelected});

  final CardioStore store;
  final String? selected;
  final void Function(String? id) onSelected;

  Future<void> _edit(BuildContext context, SavedPlan? p) async {
    final last = p == null ? const <String, LastTime>{} : await store.intervals.lastTimesOf(p.id);
    if (!context.mounted) return;
    final plan = await Navigator.of(context).push<IntervalPlan>(MaterialPageRoute(builder: (_) => IntervalPlanEditor(initial: p?.plan, lastTimes: last)));
    if (plan == null) return;
    if (p == null) {
      onSelected(await store.intervals.add(plan));
    } else {
      await store.intervals.update(p.id, plan);
    }
  }

  Future<void> _delete(BuildContext context, SavedPlan p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${p.plan.name}"?'),
        content: const Text('Its history page goes. The Interval runs you did with it stay, with their reps.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await store.intervals.delete(p.id);
    if (selected == p.id) onSelected(null);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SavedPlan>>(
        stream: store.intervals.watchPlans(),
        builder: (context, snap) {
          Icon mark(bool on) => Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? Theme.of(context).colorScheme.primary : null);
          return TileGroup(title: 'Plan', children: [
            for (final p in snap.data ?? const <SavedPlan>[])
              ListTile(
                leading: mark(selected == p.id),
                title: Text(p.plan.name),
                subtitle: Text(p.plan.describe()),
                onTap: () => onSelected(p.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (a) => switch (a) {
                    'edit' => _edit(context, p),
                    'history' => openPlanHistory(context, store, p),
                    _ => _delete(context, p),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'history', child: Text('History')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ListTile(
              leading: mark(selected == null),
              title: const Text('Free'),
              subtitle: const Text('No plan: press Switch to go between rep and recovery'),
              onTap: () => onSelected(null),
            ),
            ListTile(leading: const Icon(Icons.add), title: const Text('New plan'), onTap: () => _edit(context, null)),
          ]);
        },
      );
}

/// Opens the history of [p].
Future<void> openPlanHistory(BuildContext context, CardioStore store, SavedPlan p) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanHistoryPage(store: store, planId: p.id, name: p.plan.name)));

/// Each step kind's colour, as in Garmin: red warm-up, blue rep, grey recovery, green cool-down.
Color stepColor(StepKind k) => switch (k) {
      StepKind.warmup => const Color(0xFFE53935),
      StepKind.rep => const Color(0xFF1E88E5),
      StepKind.recovery => const Color(0xFF90A4AE),
      StepKind.cooldown => const Color(0xFF43A047),
    };

/// A Step's length and Target pace in one line: "400 m · @ 4:00 /km", "Until Next".
String stepSummary(PlanStep s) => [s.target?.describe() ?? 'Until Next', if (s.pace != null) '@ ${clock(s.pace!)} /km'].join(' · ');

/// The plan at a glance: a bar per step in running order, as wide as the step is long (a distance at its Target pace or 5:30 /km, an open step as
/// two minutes) and as tall as it is hard.
class PlanOverview extends StatelessWidget {
  const PlanOverview(this.plan, {super.key});

  final IntervalPlan plan;

  @override
  Widget build(BuildContext context) {
    int seconds(PlanStep s) => switch (s.target) {
          null => 120,
          final t when t.isTime => t.seconds!,
          final t => (t.meters! * (s.pace ?? 330) / 1000).round(),
        };
    double height(StepKind k) => switch (k) { StepKind.rep => 1, StepKind.recovery => 0.4, _ => 0.6 };
    return SizedBox(
      height: 64,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final p in plan.steps)
          Expanded(
            flex: seconds(p.step).clamp(1, 1 << 20),
            child: Container(height: 64 * height(p.kind), margin: const EdgeInsets.symmetric(horizontal: 1), color: stepColor(p.kind)),
          ),
      ]),
    );
  }
}

/// New or edit Interval plan, laid out as Garmin's editor: the overview, then the Steps and Repeats with Add step and Add repeat at the
/// bottom. Tapping a Step opens its page. [lastTimes] are the plan's Last times. Pops the plan, or nothing when backed out.
class IntervalPlanEditor extends StatefulWidget {
  const IntervalPlanEditor({super.key, this.initial, this.lastTimes = const {}});

  final IntervalPlan? initial;
  final Map<String, LastTime> lastTimes;

  @override
  State<IntervalPlanEditor> createState() => _IntervalPlanEditorState();
}

/// A copy of [list] with the item at [from] moved to [to].
List<T> _moved<T>(List<T> list, int from, int to) {
  final out = [...list];
  return out..insert(to, out.removeAt(from));
}

PlanStep _newStep(StepKind kind, StepTarget? target) => PlanStep(newPlanItemId(), kind, target);

class _IntervalPlanEditorState extends State<IntervalPlanEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late List<PlanItem> _items = widget.initial?.items ??
      [
        _newStep(StepKind.warmup, null),
        PlanRepeat(newPlanItemId(), 6, [_newStep(StepKind.rep, const StepTarget.meters(400)), _newStep(StepKind.recovery, const StepTarget.time(90))]),
        _newStep(StepKind.cooldown, null),
      ];
  String? _nameError, _stepsError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  IntervalPlan get _plan => IntervalPlan(name: _name.text.trim(), items: _items);

  LastTime? _last(PlanStep s) => switch (widget.lastTimes[s.id]) { final l? when l.fits(s) => l, _ => null };

  void _set(List<PlanItem> items) => setState(() {
        _items = [for (final i in items) if (i is! PlanRepeat || i.steps.isNotEmpty) i]; // a Repeat left with no Step goes
        _stepsError = null;
      });

  /// Replaces the Step [id] wherever it is with [to], or removes it when [to] is null.
  void _replace(String id, PlanStep? to) => _set([
        for (final i in _items)
          if (i is PlanRepeat)
            i.copy(steps: [for (final s in i.steps) if (s.id != id) s else ?to])
          else if (i.id != id)
            i
          else
            ?to,
      ]);

  PlanItem _fresh(PlanItem i) => switch (i) {
        PlanStep() => i.copy(id: newPlanItemId()),
        PlanRepeat() => PlanRepeat(newPlanItemId(), i.times, [for (final s in i.steps) s.copy(id: newPlanItemId())]),
      };

  Future<void> _open(PlanStep s) async {
    final r = await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => _StepPage(step: s, lastTime: _last)));
    if (r is PlanStep) _replace(s.id, r);
    if (r == _StepPage.removed) _replace(s.id, null);
  }

  void _useLastTimes() => _set([
        for (final i in _items)
          switch (i) {
            PlanStep() => _withLast(i),
            PlanRepeat() => i.copy(steps: [for (final s in i.steps) _withLast(s)]),
          },
      ]);

  /// [s] with its Last time as its Target pace, when it has one a Target pace can be (a walked recovery can be slower than 20:00 /km).
  PlanStep _withLast(PlanStep s) => switch (_last(s)?.paceSecPerKm.round()) { final p? when isTargetPace(p) => s.copy(pace: () => p), _ => s };

  void _save() {
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Give it a name' : null;
      _stepsError = _items.isEmpty ? 'Add a step' : null;
    });
    if (_nameError == null && _stepsError == null) Navigator.pop(context, _plan);
  }

  Widget _stepTile(PlanStep s, {required List<PopupMenuEntry<String>> moves, required void Function(String) onMove, required Widget handle}) {
    final theme = Theme.of(context);
    final last = _last(s);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(s),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: stepColor(s.kind)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(stepLabel(s.kind), style: theme.textTheme.titleMedium),
                  Text(stepSummary(s), style: theme.textTheme.bodyMedium),
                  if (last != null) Text('Last time ${formatPace(last.paceSecPerKm)} /km', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: onMove,
              itemBuilder: (_) => [const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')), ...moves, const PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
            handle,
          ]),
        ),
      ),
    );
  }

  Widget _topStep(int i, PlanStep s) => _stepTile(
        s,
        handle: ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle))),
        moves: [if (i > 0 && _items[i - 1] is PlanRepeat) const PopupMenuItem(value: 'into', child: Text('Move into repeat above'))],
        onMove: (a) => switch (a) {
          'duplicate' => _set([..._items]..insert(i + 1, _fresh(s))),
          'into' => _set([
              for (final (j, it) in _items.indexed)
                if (j == i - 1) (it as PlanRepeat).copy(steps: [...it.steps, s]) else if (j != i) it,
            ]),
          _ => _replace(s.id, null),
        },
      );

  Widget _repeat(int i, PlanRepeat r) {
    final theme = Theme.of(context);
    void times(int n) => _set([..._items]..[i] = r.copy(times: n));
    return Card(
      key: ValueKey(r.id),
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 0, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.repeat),
            const SizedBox(width: 8),
            Text('Repeat', style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton(icon: const Icon(Icons.remove), onPressed: r.times > 1 ? () => times(r.times - 1) : null),
            Text('× ${r.times}', style: theme.textTheme.titleMedium),
            IconButton(icon: const Icon(Icons.add), onPressed: r.times < 99 ? () => times(r.times + 1) : null),
            PopupMenuButton<String>(
              onSelected: (a) => _set(a == 'duplicate' ? ([..._items]..insert(i + 1, _fresh(r))) : ([..._items]..removeAt(i))),
              itemBuilder: (_) => const [PopupMenuItem(value: 'duplicate', child: Text('Duplicate')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
            ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle))),
          ]),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(right: 8),
            onReorderItem: (from, to) => _set([..._items]..[i] = r.copy(steps: _moved(r.steps, from, to))),
            children: [
              for (final (j, s) in r.steps.indexed)
                KeyedSubtree(
                  key: ValueKey(s.id),
                  child: _stepTile(
                    s,
                    handle: ReorderableDragStartListener(index: j, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle))),
                    moves: const [PopupMenuItem(value: 'out', child: Text('Move out of repeat'))],
                    onMove: (a) => switch (a) {
                      'duplicate' => _set([..._items]..[i] = r.copy(steps: [...r.steps]..insert(j + 1, s.copy(id: newPlanItemId())))),
                      'out' => _set([..._items]..[i] = r.copy(steps: [...r.steps]..removeAt(j))..insert(i + 1, s)),
                      _ => _replace(s.id, null),
                    },
                  ),
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add step'),
              onPressed: () => _set([..._items]..[i] = r.copy(steps: [...r.steps, _newStep(StepKind.rep, const StepTarget.meters(400))])),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLast = _plan.allSteps.any((s) => _last(s) != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New plan' : 'Edit plan'),
        actions: [
          if (hasLast)
            PopupMenuButton<String>(
              onSelected: (_) => _useLastTimes(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'last', child: Text('Use last time as targets'))],
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      bottomNavigationBar: BottomAction(children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.repeat),
              label: const Text('Add repeat'),
              onPressed: () => _set([
                ..._items,
                PlanRepeat(newPlanItemId(), 2, [_newStep(StepKind.rep, const StepTarget.meters(400)), _newStep(StepKind.recovery, const StepTarget.time(90))]),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add step'),
              onPressed: () => _set([..._items, _newStep(StepKind.rep, const StepTarget.meters(400))]),
            ),
          ),
        ]),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ReorderableListView(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: 'Name', hintText: '6 × 400 m', errorText: _nameError)),
              const SizedBox(height: 16),
              if (_items.isNotEmpty) PlanOverview(_plan),
              const SectionTitle('Steps'),
              if (_stepsError != null) Text(_stepsError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
            onReorderItem: (from, to) => _set(_moved(_items, from, to)),
            children: [
              for (final (i, item) in _items.indexed)
                switch (item) {
                  PlanStep() => KeyedSubtree(key: ValueKey(item.id), child: _topStep(i, item)),
                  PlanRepeat() => _repeat(i, item),
                },
            ],
          ),
        ),
      ),
    );
  }
}

/// One Step's page: its type, its duration (a distance, a time, or until Next) and its target (none, or a pace), with its Last time. Going back
/// keeps the changes when they are valid; Delete deletes the Step. Pops the Step, [removed], or nothing.
class _StepPage extends StatefulWidget {
  const _StepPage({required this.step, required this.lastTime});

  static const removed = #removed;

  final PlanStep step;
  final LastTime? Function(PlanStep) lastTime;

  @override
  State<_StepPage> createState() => _StepPageState();
}

class _StepPageState extends State<_StepPage> {
  late StepKind _kind = widget.step.kind;
  late String _duration = switch (widget.step.target) { null => 'open', final t when t.isTime => 's', _ => 'm' };
  late final _length = TextEditingController(text: switch (widget.step.target) { null => '', final t when t.isTime => clock(t.seconds!), final t => '${t.meters}' });
  late bool _hasPace = widget.step.pace != null;
  late final _pace = TextEditingController(text: widget.step.pace == null ? '' : clock(widget.step.pace!));
  String? _lengthError, _paceError;

  @override
  void dispose() {
    _length.dispose();
    _pace.dispose();
    super.dispose();
  }

  /// The length as entered, or an error message.
  (StepTarget?, String?) _readLength() {
    if (_duration == 'open') return (null, null);
    if (_duration == 'm') {
      final m = int.tryParse(_length.text.trim());
      return m == null || m <= 0 || m > 100000 ? (null, 'Enter meters, like 400') : (StepTarget.meters(m), null);
    }
    final s = parseDuration(_length.text);
    return s == null || s <= 0 || s > 86400 ? (null, 'Enter a time like 1:30') : (StepTarget.time(s), null);
  }

  /// The Target pace in seconds per km, or an error message.
  (int?, String?) _readPace() {
    if (!_hasPace) return (null, null);
    final s = parseDuration(_pace.text);
    return s == null || !isTargetPace(s) ? (null, 'Enter a pace like 4:30') : (s, null);
  }

  PlanStep? _read() {
    final (target, lengthError) = _readLength();
    final (pace, paceError) = _readPace();
    if (lengthError != null || paceError != null) return null;
    return PlanStep(widget.step.id, _kind, target, pace: pace);
  }

  void _done() {
    final (_, lengthError) = _readLength();
    final (_, paceError) = _readPace();
    setState(() {
      _lengthError = lengthError;
      _paceError = paceError;
    });
    if (lengthError == null && paceError == null) Navigator.pop(context, _read());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _read();
    final last = now == null ? null : widget.lastTime(now);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(stepLabel(_kind)),
          actions: [TextButton(onPressed: () => Navigator.pop(context, _StepPage.removed), child: const Text('Delete'))],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const SectionTitle('Step'),
              DropdownButtonFormField<StepKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Step type'),
                items: [for (final k in StepKind.values) DropdownMenuItem(value: k, child: Text(stepLabel(k)))],
                onChanged: (k) => setState(() => _kind = k!),
              ),
              const SectionTitle('Duration'),
              DropdownButtonFormField<String>(
                initialValue: _duration,
                decoration: const InputDecoration(labelText: 'Duration type'),
                items: const [
                  DropdownMenuItem(value: 'm', child: Text('Distance')),
                  DropdownMenuItem(value: 's', child: Text('Time')),
                  DropdownMenuItem(value: 'open', child: Text('Until Next')),
                ],
                onChanged: (d) => setState(() {
                  _duration = d!;
                  _length.clear();
                  _lengthError = null;
                }),
              ),
              if (_duration != 'open') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _length,
                  keyboardType: _duration == 'm' ? TextInputType.number : TextInputType.datetime,
                  decoration: InputDecoration(labelText: _duration == 'm' ? 'Meters' : 'Time (m:ss)', hintText: _duration == 'm' ? '400' : '1:30', errorText: _lengthError),
                  onChanged: (_) => setState(() {}),
                ),
              ] else
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('The step lasts until you press Next.')),
              const SectionTitle('Target'),
              DropdownButtonFormField<bool>(
                initialValue: _hasPace,
                decoration: const InputDecoration(labelText: 'Target type'),
                items: const [DropdownMenuItem(value: false, child: Text('No target')), DropdownMenuItem(value: true, child: Text('Pace'))],
                onChanged: (v) => setState(() {
                  _hasPace = v!;
                  _paceError = null;
                }),
              ),
              if (_hasPace) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pace,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(labelText: 'Pace (m:ss /km)', hintText: last == null ? '4:30' : formatPace(last.paceSecPerKm), errorText: _paceError),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (last != null) ...[
                const SizedBox(height: 16),
                Text('Last time ${formatPace(last.paceSecPerKm)} /km', style: theme.textTheme.titleMedium),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Every Interval run done with one plan, newest first: average rep pace and fastest rep, with a chart of the average over time.
class PlanHistoryPage extends StatelessWidget {
  const PlanHistoryPage({super.key, required this.store, required this.planId, required this.name});

  final CardioStore store;
  final String planId, name;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: StreamBuilder<List<HistoryEntry>>(
        stream: store.intervals.watchHistory(planId),
        builder: (context, snap) {
          final entries = snap.data ?? const <HistoryEntry>[];
          if (snap.hasData && entries.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No Interval runs with this plan yet.')));
          final charted = [for (final e in entries.reversed) if (e.summary != null) (e.run.startedAt.toLocal(), -e.summary!.avgPaceSecPerKm)]; // negated: faster is higher
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            if (charted.length >= 2) SeriesChart('Average rep pace /km', charted, leftReserved: 44, leftLabel: (v) => formatPace(-v)),
            TileGroup(title: 'Runs', children: [
              for (final e in entries)
                ListTile(
                  title: Text(loc.formatMediumDate(e.run.startedAt.toLocal())),
                  subtitle: Text(switch (e.summary) {
                    null => 'No reps recorded',
                    final s => '${s.reps} reps · average ${formatPace(s.avgPaceSecPerKm)} /km · fastest ${formatPace(s.fastest.paceSecPerKm!)} /km',
                  }),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openRun(context, store, e.run.id),
                ),
            ]),
          ]);
        },
      ),
    );
  }
}

/// An Interval run's steps on its Run page: distance, time, pace and average heart rate of each; everything but the reps is greyed.
/// A free one that has no plan yet offers Save as plan; one run to a plan links to its history.
class StepsSection extends StatelessWidget {
  const StepsSection({super.key, required this.store, required this.run, required this.track});

  final CardioStore store;
  final CardioData run;
  final Track track;

  Future<void> _saveAsPlan(BuildContext context) async {
    final name = TextEditingController(text: 'My intervals');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as plan'),
        content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) await store.intervals.saveAsPlan(run.id, name.text);
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = track.steps ?? const <StepMark>[];
    if (steps.isEmpty) return const SizedBox.shrink();
    final grey = Theme.of(context).disabledColor;
    final planId = run.intervalPlanId;
    var rep = 0;
    return TileGroup(title: 'Reps', children: [
      for (final s in steps)
        () {
          if (s.kind == StepKind.rep) rep++;
          final hr = stepAvgHr(track, s);
          final style = s.kind == StepKind.rep ? null : TextStyle(color: grey);
          return ListTile(
            dense: true,
            leading: SizedBox(width: 80, child: Text(stepLabel(s.kind, rep: s.kind == StepKind.rep ? rep : null), style: style)),
            title: Text('${(s.meters / 1000).toStringAsFixed(2)} km · ${formatDuration(s.sec)}${s.paceSecPerKm == null ? '' : ' · ${formatPace(s.paceSecPerKm!)} /km'}', style: style),
            trailing: Text(hr == null ? '' : '$hr bpm', style: style),
          );
        }(),
      if (planId == null)
        ListTile(leading: const Icon(Icons.bookmark_add_outlined), title: const Text('Save as plan'), onTap: () => _saveAsPlan(context))
      else
        StreamBuilder<List<SavedPlan>>(
          stream: store.intervals.watchPlans(),
          builder: (context, snap) => switch (snap.data?.where((p) => p.id == planId).firstOrNull) {
            null => const SizedBox.shrink(), // the plan was deleted
            final p => ListTile(leading: const Icon(Icons.history), title: Text('${p.plan.name} history'), trailing: const Icon(Icons.chevron_right), onTap: () => openPlanHistory(context, store, p)),
          },
        ),
    ]);
  }
}
