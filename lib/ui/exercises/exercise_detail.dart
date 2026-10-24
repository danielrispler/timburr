import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/records.dart';
import '../../data/workouts.dart';

const loadTypes = ['weighted', 'bodyweight', 'timed'];

class ExerciseDetail extends StatefulWidget {
  const ExerciseDetail({super.key, required this.catalog, required this.entry, this.workouts});

  final Catalog catalog;
  final WorkoutStore? workouts;
  final CatalogEntry entry;

  @override
  State<ExerciseDetail> createState() => _ExerciseDetailState();
}

class _ExerciseDetailState extends State<ExerciseDetail> {
  late CatalogEntry entry = widget.entry;
  late final _sessions = widget.workouts
      ?.finishedSessions(entry.rowId ?? libraryRowId(entry.libraryId!));

  bool get _custom => entry.libraryId == null;

  /// Writes through the catalog, then re-reads the merged entry.
  Future<void> _update({String? loadType, String? stickyNote}) async {
    final c = widget.catalog;
    final id = _custom
        ? entry.rowId!
        : await c.configureLibrary(entry.libraryId!, loadType: loadType, stickyNote: stickyNote);
    if (_custom) {
      if (loadType != null) {
        await c.saveCustom(
            id: id, name: entry.name, loadType: loadType, muscles: entry.muscles, equipment: entry.equipment);
      }
      if (stickyNote != null) await c.setStickyNote(id, stickyNote);
    }
    final fresh = await c.byId(id);
    if (mounted && fresh != null) setState(() => entry = fresh);
  }

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: entry.stickyNote);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sticky note'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: null),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (note != null) await _update(stickyNote: note);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: const Text('It disappears from lists. Past workouts keep it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.catalog.deleteCustom(entry.rowId!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _edit() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CustomExerciseForm(catalog: widget.catalog, entry: entry)));
    final fresh = await widget.catalog.byId(entry.rowId!);
    if (mounted && fresh != null) setState(() => entry = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String label, String? value) => ListTile(dense: true, title: Text(label), trailing: Text(value ?? '-'));
    return Scaffold(
      appBar: AppBar(title: Text(entry.name), actions: [
        if (_custom) ...[
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: _edit),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              row('Category', entry.category),
              ListTile(
                dense: true,
                title: const Text('Load type'),
                trailing: DropdownButton<String>(
                  value: entry.loadType,
                  items: [for (final t in loadTypes) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (t) => _update(loadType: t),
                ),
              ),
              row('Equipment', entry.equipment),
              row('Primary muscles', entry.muscles.join(', ')),
              if (entry.secondaryMuscles.isNotEmpty) row('Secondary muscles', entry.secondaryMuscles.join(', ')),
              ListTile(
                title: const Text('Sticky note'),
                subtitle: Text(entry.stickyNote?.isNotEmpty == true ? entry.stickyNote! : 'Tap to add'),
                trailing: const Icon(Icons.edit_note),
                onTap: _editNote,
              ),
              if (_sessions case final sessions?)
                FutureBuilder(
                  future: sessions,
                  builder: (context, snap) => snap.hasData
                      ? _Stats(loadType: entry.loadType ?? 'weighted', sessions: snap.data!)
                      : const SizedBox.shrink(),
                ),
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

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Last session, records and per-session charts.
class _Stats extends StatelessWidget {
  const _Stats({required this.loadType, required this.sessions});

  final String loadType;
  final List<(DateTime, List<WorkoutSet>)> sessions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget heading(String s) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(s, style: text.titleMedium));
    final last = sessions.lastWhere((s) => s.$2.any((x) => x.done), orElse: () => (DateTime(0), []));
    if (last.$2.isEmpty) {
      return const ListTile(leading: Icon(Icons.show_chart), title: Text('No history yet'));
    }
    final rec = records(loadType, [for (final (_, sets) in sessions) sets]);
    final series = chartSeries(sessions);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('Last session · ${_date(last.$1)}'),
      for (final s in last.$2.where((s) => s.done))
        ListTile(
          dense: true,
          title: Text(switch (loadType) {
            'timed' => '${s.durationSec ?? 0} s',
            'bodyweight' => '${s.reps ?? 0} reps${(s.weightKg ?? 0) > 0 ? ' +${_num(s.weightKg!)} kg' : ''}',
            _ => '${_num(s.weightKg ?? 0)} kg × ${s.reps ?? 0}',
          }),
        ),
      heading('Records'),
      for (final MapEntry(:key, :value) in rec.entries)
        ListTile(dense: true, title: Text(key), trailing: Text(_num(value))),
      if (loadType == 'weighted') ...[
        _Chart('Max weight (kg)', series.maxWeight),
        _Chart('e1RM (kg)', series.e1rm),
        _Chart('Volume (kg)', series.volume),
      ],
    ]);
  }
}

class _Chart extends StatelessWidget {
  const _Chart(this.title, this.points);

  final String title;
  final Series points;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 2,
          child: LineChart(LineChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: points.length > 4 ? (points.length / 4).ceilToDouble() : 1,
                  getTitlesWidget: (x, meta) {
                    final i = x.toInt();
                    if (i != x || i < 0 || i >= points.length) return const SizedBox.shrink();
                    final d = points[i].$1;
                    return SideTitleWidget(meta: meta, child: Text('${d.day}/${d.month}'));
                  },
                ),
              ),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            ),
            lineBarsData: [
              LineChartBarData(
                // shortcut: x is session index, not time, so gaps between sessions are evenly spaced.
                spots: [for (final (i, (_, v)) in points.indexed) FlSpot(i.toDouble(), v)],
                color: color,
                barWidth: 3,
                dotData: FlDotData(show: points.length < 30),
              ),
            ],
          )),
        ),
      ]),
    );
  }
}

/// Create (no [entry]) or edit a custom exercise.
class CustomExerciseForm extends StatefulWidget {
  const CustomExerciseForm({super.key, required this.catalog, this.entry});

  final Catalog catalog;
  final CatalogEntry? entry;

  @override
  State<CustomExerciseForm> createState() => _CustomExerciseFormState();
}

class _CustomExerciseFormState extends State<CustomExerciseForm> {
  late final _name = TextEditingController(text: widget.entry?.name);
  late final _muscles = TextEditingController(text: widget.entry?.muscles.join(', '));
  late final _equipment = TextEditingController(text: widget.entry?.equipment);
  late String _loadType = widget.entry?.loadType ?? 'weighted';

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final equipment = _equipment.text.trim();
    await widget.catalog.saveCustom(
      id: widget.entry?.rowId,
      name: name,
      loadType: _loadType,
      muscles: [for (final m in _muscles.text.split(',')) if (m.trim().isNotEmpty) m.trim().toLowerCase()],
      equipment: equipment.isEmpty ? null : equipment.toLowerCase(),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'New exercise' : 'Edit exercise'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _name, autofocus: widget.entry == null, decoration: deco('Name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _loadType,
                decoration: deco('Load type'),
                items: [for (final t in loadTypes) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (t) => setState(() => _loadType = t!),
              ),
              const SizedBox(height: 12),
              TextField(controller: _muscles, decoration: deco('Muscles (comma separated)')),
              const SizedBox(height: 12),
              TextField(controller: _equipment, decoration: deco('Equipment')),
            ],
          ),
        ),
      ),
    );
  }
}
