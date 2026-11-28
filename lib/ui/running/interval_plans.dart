import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                trailing: IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showActions(context, p.plan.name, [
                    (icon: Icons.edit_outlined, label: 'Edit', onTap: () => _edit(context, p), danger: false),
                    (icon: Icons.history, label: 'History', onTap: () => openPlanHistory(context, store, p), danger: false),
                    (icon: Icons.delete_outline, label: 'Delete', onTap: () => _delete(context, p), danger: true),
                  ]),
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

/// Each step kind's icon.
IconData stepIcon(StepKind k) => switch (k) {
      StepKind.warmup => Icons.local_fire_department_outlined,
      StepKind.rep => Icons.directions_run,
      StepKind.recovery => Icons.directions_walk,
      StepKind.cooldown => Icons.ac_unit,
    };

/// Text that reads on [background]: white on a dark colour, near-black on a light one.
Color readableOn(Color background) => ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : Colors.black87;

/// A Step's length and Target pace in one line: "400 m · @ 4:00 /km", "Until Next".
String stepSummary(PlanStep s) => [s.target?.describe() ?? 'Until Next', if (s.pace != null) '@ ${clock(s.pace!)} /km'].join(' · ');

/// Typing a time or a pace: digits only, filled in from the right with the colon put in by itself ("1" 0:01, "130" 1:30, "1030" 10:30).
class ClockInputFormatter extends TextInputFormatter {
  const ClockInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > 4) return oldValue; // 99:59 at most
    if (digits.isEmpty) return TextEditingValue.empty;
    final p = digits.padLeft(3, '0');
    final text = '${int.parse(p.substring(0, p.length - 2))}:${p.substring(p.length - 2)}';
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// One choice of an actions sheet.
typedef SheetAction = ({IconData icon, String label, VoidCallback onTap, bool danger});

/// A bottom sheet of [actions], titled [title]: the app's menu for a row, in place of a popup menu.
Future<void> showActions(BuildContext context, String title, List<SheetAction> actions) => showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            for (final a in actions)
              ListTile(
                leading: Icon(a.icon, color: a.danger ? scheme.error : null),
                title: Text(a.label, style: a.danger ? TextStyle(color: scheme.error) : null),
                onTap: () {
                  Navigator.pop(context);
                  a.onTap();
                },
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );

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
    return Container(
      height: 88,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final p in plan.steps)
          Expanded(
            flex: seconds(p.step).clamp(1, 1 << 20),
            child: Container(
              height: 64 * height(p.kind),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(color: stepColor(p.kind), borderRadius: BorderRadius.circular(4)),
            ),
          ),
      ]),
    );
  }
}

/// New or edit Interval plan, laid out as Garmin's editor: the overview, then the Steps and Repeats with Add step and Add repeat at the
/// bottom. Tapping a Step opens its page; swiping a Step or Repeat left deletes it, with Undo. [lastTimes] are the plan's Last times. Pops the
/// plan, or nothing when backed out.
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

PlanStep _newRep() => _newStep(StepKind.rep, const StepTarget.meters(400));

PlanRepeat _newRepeat(int times) => PlanRepeat(newPlanItemId(), times, [_newRep(), _newStep(StepKind.recovery, const StepTarget.time(90))]);

/// The row being dragged: a little larger, with no box of its own behind it (each row is its own rounded card).
Widget _lifted(Widget child, int index, Animation<double> animation) => AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Material(type: MaterialType.transparency, child: Transform.scale(scale: 1 + 0.03 * Curves.easeOut.transform(animation.value), child: child)),
      child: child,
    );

Widget _handle(int index) => ReorderableDragStartListener(index: index, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_indicator)));

class _IntervalPlanEditorState extends State<IntervalPlanEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late List<PlanItem> _items = widget.initial?.items ?? [_newStep(StepKind.warmup, null), _newRepeat(6), _newStep(StepKind.cooldown, null)];
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

  /// Deletes the Step or Repeat [id], with Undo.
  void _delete(String id, String what) {
    final before = _items;
    if (_items.any((i) => i.id == id)) {
      _set([for (final i in _items) if (i.id != id) i]);
    } else {
      _replace(id, null);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what deleted'), action: SnackBarAction(label: 'Undo', onPressed: () => _set(before))));
  }

  PlanItem _fresh(PlanItem i) => switch (i) {
        PlanStep() => i.copy(id: newPlanItemId()),
        PlanRepeat() => PlanRepeat(newPlanItemId(), i.times, [for (final s in i.steps) s.copy(id: newPlanItemId())]),
      };

  Future<void> _open(PlanStep s) async {
    final r = await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => _StepPage(step: s, lastTime: _last)));
    if (r is PlanStep) _replace(s.id, r);
    if (r == _StepPage.removed) _delete(s.id, stepLabel(s.kind));
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

  /// Swiping left reveals this behind a row.
  Widget _swipeBackground() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 24),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(28)),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }

  Widget _stepTile(PlanStep s, {required List<SheetAction> moves, required VoidCallback duplicate, required Widget handle}) {
    final theme = Theme.of(context);
    final last = _last(s), color = stepColor(s.kind), label = stepLabel(s.kind);
    return Dismissible(
      key: ValueKey('dismiss-${s.id}'),
      direction: DismissDirection.endToStart,
      background: _swipeBackground(),
      onDismissed: (_) => _delete(s.id, label),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                child: Icon(stepIcon(s.kind), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: theme.textTheme.titleMedium),
                  Text(stepSummary(s), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (last != null) Text('Last time ${formatPace(last.paceSecPerKm)} /km', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                ]),
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () => showActions(context, label, [
                  (icon: Icons.copy_outlined, label: 'Duplicate', onTap: duplicate, danger: false),
                  ...moves,
                  (icon: Icons.delete_outline, label: 'Delete', onTap: () => _delete(s.id, label), danger: true),
                ]),
              ),
              handle,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _topStep(int i, PlanStep s) => _stepTile(
        s,
        handle: _handle(i),
        duplicate: () => _set([..._items]..insert(i + 1, _fresh(s))),
        moves: [
          if (i > 0 && _items[i - 1] is PlanRepeat)
            (
              icon: Icons.move_up,
              label: 'Move into repeat above',
              onTap: () => _set([
                    for (final (j, it) in _items.indexed)
                      if (j == i - 1) (it as PlanRepeat).copy(steps: [...it.steps, s]) else if (j != i) it,
                  ]),
              danger: false,
            ),
        ],
      );

  Widget _repeat(int i, PlanRepeat r) {
    final theme = Theme.of(context);
    void times(int n) => _set([..._items]..[i] = r.copy(times: n));
    return Dismissible(
      key: ValueKey('dismiss-${r.id}'),
      direction: DismissDirection.endToStart,
      background: _swipeBackground(),
      onDismissed: (_) => _delete(r.id, 'Repeat'),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.repeat, color: theme.colorScheme.onSecondaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('Repeat', style: theme.textTheme.titleMedium)),
              DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(24)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(visualDensity: VisualDensity.compact, tooltip: 'Fewer rounds', icon: const Icon(Icons.remove), onPressed: r.times > 1 ? () => times(r.times - 1) : null),
                  Text('× ${r.times}', style: theme.textTheme.titleMedium),
                  IconButton(visualDensity: VisualDensity.compact, tooltip: 'More rounds', icon: const Icon(Icons.add), onPressed: r.times < 99 ? () => times(r.times + 1) : null),
                ]),
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () => showActions(context, 'Repeat × ${r.times}', [
                  (icon: Icons.copy_outlined, label: 'Duplicate', onTap: () => _set([..._items]..insert(i + 1, _fresh(r))), danger: false),
                  (icon: Icons.delete_outline, label: 'Delete', onTap: () => _delete(r.id, 'Repeat'), danger: true),
                ]),
              ),
              _handle(i),
            ]),
            const SizedBox(height: 6),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: _lifted,
              padding: const EdgeInsets.only(right: 12),
              onReorderItem: (from, to) => _set([..._items]..[i] = r.copy(steps: _moved(r.steps, from, to))),
              children: [
                for (final (j, s) in r.steps.indexed)
                  KeyedSubtree(
                    key: ValueKey(s.id),
                    child: _stepTile(
                      s,
                      handle: _handle(j),
                      duplicate: () => _set([..._items]..[i] = r.copy(steps: [...r.steps]..insert(j + 1, s.copy(id: newPlanItemId())))),
                      moves: [
                        (icon: Icons.move_down, label: 'Move out of repeat', onTap: () => _set([..._items]..[i] = r.copy(steps: [...r.steps]..removeAt(j))..insert(i + 1, s)), danger: false),
                      ],
                    ),
                  ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add step'),
                onPressed: () => _set([..._items]..[i] = r.copy(steps: [...r.steps, _newRep()])),
              ),
            ),
          ]),
        ),
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
          if (hasLast) IconButton(tooltip: 'Use last time as targets', icon: const Icon(Icons.history), onPressed: _useLastTimes),
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: BottomAction(children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Row(children: [
              Expanded(child: FilledButton.tonalIcon(icon: const Icon(Icons.repeat), label: const Text('Add repeat'), onPressed: () => _set([..._items, _newRepeat(2)]))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Add step'), onPressed: () => _set([..._items, _newRep()]))),
            ]),
          ),
        ),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            buildDefaultDragHandles: false,
            proxyDecorator: _lifted,
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
                  PlanRepeat() => KeyedSubtree(key: ValueKey(item.id), child: _repeat(i, item)),
                },
            ],
          ),
        ),
      ),
    );
  }
}

/// One Step's page: its type, its duration (a distance, a time, or until Next) and its Target pace, with its Last time. Going back keeps the
/// changes when they are valid; Delete deletes the Step. Pops the Step, [removed], or nothing.
class _StepPage extends StatefulWidget {
  const _StepPage({required this.step, required this.lastTime});

  static const removed = #removed;

  final PlanStep step;
  final LastTime? Function(PlanStep) lastTime;

  @override
  State<_StepPage> createState() => _StepPageState();
}

enum _Length { distance, time, open }

class _StepPageState extends State<_StepPage> {
  late StepKind _kind = widget.step.kind;
  late _Length _length = switch (widget.step.target) { null => _Length.open, final t when t.isTime => _Length.time, _ => _Length.distance };
  late final _size = TextEditingController(text: switch (widget.step.target) { null => '', final t when t.isTime => clock(t.seconds!), final t => '${t.meters}' });
  late bool _hasPace = widget.step.pace != null;
  late final _pace = TextEditingController(text: widget.step.pace == null ? '' : clock(widget.step.pace!));
  String? _sizeError, _paceError;

  @override
  void dispose() {
    _size.dispose();
    _pace.dispose();
    super.dispose();
  }

  /// The length as entered, or an error message.
  (StepTarget?, String?) _readSize() {
    switch (_length) {
      case _Length.open:
        return (null, null);
      case _Length.distance:
        final m = int.tryParse(_size.text.trim());
        return m == null || m <= 0 || m > 100000 ? (null, 'Enter meters, like 400') : (StepTarget.meters(m), null);
      case _Length.time:
        final s = parseDuration(_size.text);
        return s == null || s <= 0 || s > 86400 ? (null, 'Enter a time like 1:30') : (StepTarget.time(s), null);
    }
  }

  /// The Target pace in seconds per km, or an error message.
  (int?, String?) _readPace() {
    if (!_hasPace) return (null, null);
    final s = parseDuration(_pace.text);
    return s == null || !isTargetPace(s) ? (null, 'Enter a pace like 4:30') : (s, null);
  }

  void _done() {
    final (target, sizeError) = _readSize();
    final (pace, paceError) = _readPace();
    setState(() {
      _sizeError = sizeError;
      _paceError = paceError;
    });
    if (sizeError == null && paceError == null) Navigator.pop(context, PlanStep(widget.step.id, _kind, target, pace: pace));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (target, sizeError) = _readSize();
    final last = sizeError == null ? widget.lastTime(PlanStep(widget.step.id, _kind, target)) : null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(stepLabel(_kind)),
          actions: [
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => Navigator.pop(context, _StepPage.removed)),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              const SectionTitle('Step type'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in StepKind.values)
                  ChoiceChip(
                    avatar: Icon(stepIcon(k), color: stepColor(k)),
                    label: Text(stepLabel(k)),
                    selected: _kind == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ]),
              const SectionTitle('Duration'),
              SegmentedButton<_Length>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Length.distance, label: Text('Distance')),
                  ButtonSegment(value: _Length.time, label: Text('Time')),
                  ButtonSegment(value: _Length.open, label: Text('Until Next')),
                ],
                selected: {_length},
                onSelectionChanged: (s) => setState(() {
                  _length = s.single;
                  _size.clear();
                  _sizeError = null;
                }),
              ),
              const SizedBox(height: 12),
              switch (_length) {
                _Length.open => Text('The step lasts until you press Next.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                _Length.distance => TextField(
                    key: const ValueKey('distance'),
                    controller: _size,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: 'Distance', hintText: '400', suffixText: 'm', errorText: _sizeError),
                    onChanged: (_) => setState(() {}),
                  ),
                _Length.time => TextField(
                    key: const ValueKey('time'),
                    controller: _size,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ClockInputFormatter()],
                    decoration: InputDecoration(labelText: 'Time', hintText: '1:30', suffixText: 'min:sec', errorText: _sizeError),
                    onChanged: (_) => setState(() {}),
                  ),
              },
              const SectionTitle('Target pace'),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: false, label: Text('None')), ButtonSegment(value: true, label: Text('Pace'))],
                selected: {_hasPace},
                onSelectionChanged: (s) => setState(() {
                  _hasPace = s.single;
                  _paceError = null;
                }),
              ),
              if (_hasPace) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pace,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ClockInputFormatter()],
                  decoration: InputDecoration(labelText: 'Pace', hintText: last == null ? '4:30' : formatPace(last.paceSecPerKm), suffixText: '/km', errorText: _paceError),
                ),
              ],
              if (last != null) ...[
                const SizedBox(height: 20),
                Card(
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: ListTile(leading: const Icon(Icons.history), title: Text('Last time ${formatPace(last.paceSecPerKm)} /km')),
                ),
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
