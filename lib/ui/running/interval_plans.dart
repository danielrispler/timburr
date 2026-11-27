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

/// "Warm-up", "Rep 3", "Recovery", "Cool-down".
String stepLabel(StepKind kind, {int? rep}) => switch (kind) {
      StepKind.warmup => 'Warm-up',
      StepKind.rep => rep == null ? 'Rep' : 'Rep $rep',
      StepKind.recovery => 'Recovery',
      StepKind.cooldown => 'Cool-down',
    };

/// The setup screen's choice of plan: each saved plan (with Edit, History and Delete), Free, and New plan. [selected] null is Free.
class PlanPicker extends StatelessWidget {
  const PlanPicker({super.key, required this.store, required this.selected, required this.onSelected});

  final CardioStore store;
  final String? selected;
  final void Function(String? id) onSelected;

  Future<void> _edit(BuildContext context, SavedPlan? p) async {
    final plan = await Navigator.of(context).push<IntervalPlan>(MaterialPageRoute(builder: (_) => IntervalPlanEditor(initial: p?.plan)));
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

/// One step's size in the editor: none (warm-up and cool-down only), a distance in meters, or a time.
class _StepField {
  _StepField(StepTarget? t, {required this.optional})
      : mode = t == null ? (optional ? 'none' : 'm') : t.isTime ? 's' : 'm',
        text = TextEditingController(text: t == null ? '' : t.isTime ? clock(t.seconds!) : '${t.meters}');

  final bool optional;
  String mode; // none, m, s
  final TextEditingController text;

  /// The target, or an error message.
  (StepTarget?, String?) read() {
    if (mode == 'none') return (null, null);
    if (mode == 'm') {
      final m = int.tryParse(text.text.trim());
      return m == null || m <= 0 || m > 100000 ? (null, 'Enter meters, like 400') : (StepTarget.meters(m), null);
    }
    final s = parseDuration(text.text);
    return s == null || s <= 0 || s > 86400 ? (null, 'Enter a time like 1:30') : (StepTarget.time(s), null);
  }
}

/// New or edit Interval plan. Pops the plan, or nothing when backed out.
class IntervalPlanEditor extends StatefulWidget {
  const IntervalPlanEditor({super.key, this.initial});

  final IntervalPlan? initial;

  @override
  State<IntervalPlanEditor> createState() => _IntervalPlanEditorState();
}

class _IntervalPlanEditorState extends State<IntervalPlanEditor> {
  late final p = widget.initial;
  late final _name = TextEditingController(text: p?.name ?? '');
  late final _reps = TextEditingController(text: '${p?.reps ?? 6}');
  late final _fields = {
    'warmup': _StepField(p?.warmup, optional: true),
    'rep': _StepField(p?.rep ?? const StepTarget.meters(400), optional: false),
    'recovery': _StepField(p?.recovery ?? const StepTarget.time(90), optional: false),
    'cooldown': _StepField(p?.cooldown, optional: true),
  };
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _reps.dispose();
    for (final f in _fields.values) {
      f.text.dispose();
    }
    super.dispose();
  }

  void _save() {
    final errors = <String, String>{};
    if (_name.text.trim().isEmpty) errors['name'] = 'Give it a name';
    final reps = int.tryParse(_reps.text.trim());
    if (reps == null || reps < 1 || reps > 100) errors['reps'] = 'Enter 1 to 100';
    final t = <String, StepTarget?>{};
    for (final MapEntry(:key, :value) in _fields.entries) {
      final (target, error) = value.read();
      if (error != null) errors[key] = error;
      t[key] = target;
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    Navigator.pop(context, IntervalPlan(name: _name.text.trim(), warmup: t['warmup'], reps: reps!, rep: t['rep']!, recovery: t['recovery']!, cooldown: t['cooldown']));
  }

  Widget _step(String key, String title) {
    final f = _fields[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            if (f.optional) const ButtonSegment(value: 'none', label: Text('None')),
            const ButtonSegment(value: 'm', label: Text('Distance')),
            const ButtonSegment(value: 's', label: Text('Time')),
          ],
          selected: {f.mode},
          onSelectionChanged: (s) => setState(() {
            f.mode = s.single;
            f.text.clear();
          }),
        ),
        if (f.mode != 'none')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: f.text,
              keyboardType: f.mode == 'm' ? TextInputType.number : TextInputType.datetime,
              decoration: InputDecoration(labelText: f.mode == 'm' ? 'Meters' : 'Time (m:ss)', hintText: f.mode == 'm' ? '400' : '1:30', errorText: _errors[key]),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(p == null ? 'New plan' : 'Edit plan')),
        bottomNavigationBar: BottomAction(children: [FilledButton(onPressed: _save, child: const Text('Save'))]),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: 'Name', hintText: '6 × 400 m', errorText: _errors['name'])),
              const SizedBox(height: 16),
              _step('warmup', 'Warm-up'),
              TextField(controller: _reps, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Reps', errorText: _errors['reps'])),
              const SizedBox(height: 16),
              _step('rep', 'Each rep'),
              _step('recovery', 'Recovery after each rep'),
              _step('cooldown', 'Cool-down'),
            ]),
          ),
        ),
      );
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
