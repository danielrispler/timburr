import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/run_analysis.dart';
import '../core/text_direction.dart';
import '../core/theme.dart';
import 'activity_timer.dart';

/// New or edit cardio session. Pace updates as distance and duration are typed.
class CardioForm extends StatefulWidget {
  const CardioForm({super.key, required this.store, this.existing, this.type, this.startedAt, this.durationSec});

  final CardioStore store;
  final CardioData? existing;

  /// Prefills for a new session, e.g. from the activity timer.
  final String? type;
  final DateTime? startedAt;
  final int? durationSec;

  @override
  State<CardioForm> createState() => _CardioFormState();
}

class _CardioFormState extends State<CardioForm> {
  late final c = widget.existing;
  late String? _type = c?.type ?? widget.type ?? 'run';
  late DateTime _at = (c?.startedAt ?? widget.startedAt ?? DateTime.now()).toLocal(); // imported and pulled Runs carry UTC
  late final _km = TextEditingController(text: c?.distanceKm == null ? '' : _num(roundTo(c!.distanceKm!, 3)));
  late final _dur = TextEditingController(text: switch (c?.durationSec ?? widget.durationSec) { final s? => formatDuration(s), null => '' });
  late final _hr = TextEditingController(text: c?.avgHr?.toString() ?? '');
  late final _incline = TextEditingController(text: c?.inclinePct == null ? '' : _num(c!.inclinePct!));
  late final _steps = TextEditingController(text: c?.steps?.toString() ?? '');
  late final _calories = TextEditingController(text: c?.calories?.toString() ?? '');
  late final _rpe = TextEditingController(text: c?.rpe?.toString() ?? '');
  late final _notes = TextEditingController(text: c?.notes ?? '');
  late final _title = TextEditingController(text: c?.title ?? '');
  late DateTime _end = _at.add(Duration(seconds: c?.elapsedSec ?? c?.durationSec ?? 0)); // edit mode only: Elapsed time is end minus start
  Map<String, String> _errors = {};

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final t in [_km, _dur, _hr, _incline, _steps, _calories, _rpe, _notes, _title]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _at, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    final at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute);
    setState(() {
      _end = _end.add(at.difference(_at)); // moving the start keeps the Elapsed time
      _at = at;
    });
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end));
    if (t == null) return;
    var end = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute);
    if (!end.isAfter(_at)) end = end.add(const Duration(days: 1)); // a run past midnight
    setState(() => _end = end);
  }

  Future<void> _save() async {
    final errors = validateCardio(
        type: _type, distance: _km.text, duration: _dur.text, avgHr: _hr.text, incline: _type == 'treadmill' ? _incline.text : '', rpe: _rpe.text,
        steps: _type == 'treadmill' ? _steps.text : '', calories: _type == 'treadmill' ? _calories.text : '');
    final elapsed = _end.difference(_at).inSeconds;
    if (c != null && elapsed <= 0) errors['elapsed'] = 'End must be after the start';
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    String? opt(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();
    if (c != null) {
      // Only what changed is saved, and only that is marked as edited, so a later recording still fills the rest.
      final old = c!, fields = <String, Object?>{};
      void diff(String column, Object? now, Object? before) {
        if (now != before) fields[column] = now;
      }

      diff('type', _type, old.type);
      if (!_at.isAtSameMomentAs(old.startedAt)) fields['started_at'] = _at;
      diff('distance_km', parseNum(_km.text), old.distanceKm == null ? null : roundTo(old.distanceKm!, 3)); // as the field shows it
      diff('duration_sec', parseDuration(_dur.text), old.durationSec);
      diff('elapsed_sec', elapsed, old.elapsedSec ?? old.durationSec);
      diff('avg_hr', opt(_hr) == null ? null : int.parse(opt(_hr)!), old.avgHr);
      diff('incline_pct', _type != 'treadmill' || opt(_incline) == null ? null : parseNum(_incline.text), old.inclinePct);
      diff('steps', _type != 'treadmill' || opt(_steps) == null ? null : int.parse(opt(_steps)!), old.steps);
      diff('calories', _type != 'treadmill' || opt(_calories) == null ? null : int.parse(opt(_calories)!), old.calories);
      diff('rpe', opt(_rpe) == null ? null : int.parse(opt(_rpe)!), old.rpe);
      diff('title', opt(_title), old.title);
      diff('notes', opt(_notes), old.notes);
      if (fields.isNotEmpty) await widget.store.edit(old.id, fields);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await widget.store.save(
      id: c?.id,
      type: _type!,
      startedAt: _at,
      distanceKm: parseNum(_km.text),
      durationSec: parseDuration(_dur.text)!,
      avgHr: opt(_hr) == null ? null : int.parse(opt(_hr)!),
      inclinePct: _type != 'treadmill' || opt(_incline) == null ? null : parseNum(_incline.text),
      rpe: opt(_rpe) == null ? null : int.parse(opt(_rpe)!),
      notes: opt(_notes),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this session?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(c!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(String key, TextEditingController t, String label,
          {TextInputType keyboard = const TextInputType.numberWithOptions(decimal: true), String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: t,
          textDirection: textDirectionOf(t.text),
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: label, hintText: hint, errorText: _errors[key]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final sec = parseDuration(_dur.text);
    final pace = sec == null ? null : paceSecPerKm(parseNum(_km.text), sec);
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Log ${activityLabel(_type ?? 'run')}' : 'Edit ${activityLabel(c!.type)}'),
        actions: [
          if (c != null) IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: _delete),
        ],
      ),
      bottomNavigationBar: BottomAction(children: [FilledButton(onPressed: _save, child: const Text('Save'))]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in cardioTypes)
                  ChoiceChip(
                    avatar: Icon(activityIcon(t)),
                    label: Text(activityLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ]),
              if (_errors['type'] case final e?) Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: groupedTile(
                    0,
                    1,
                    ListTile(
                      leading: const IconTile(Icons.event),
                      title: Text('${loc.formatMediumDate(_at)}, ${TimeOfDay.fromDateTime(_at).format(context)}'),
                      onTap: _pickDate,
                    )),
              ),
              if (c != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: groupedTile(
                      0,
                      1,
                      ListTile(
                        leading: const IconTile(Icons.flag),
                        title: Text('Ends ${TimeOfDay.fromDateTime(_end).format(context)}'),
                        subtitle: Text(_errors['elapsed'] ?? 'Elapsed ${formatDuration(_end.difference(_at).inSeconds.clamp(0, int4Max))}'),
                        onTap: _pickEnd,
                      )),
                ),
              if (c != null) _field('title', _title, 'Title', keyboard: TextInputType.text, hint: runTitle(_at, treadmill: _type == 'treadmill')),
              _field('distance', _km, 'Distance (km)'),
              _field('duration', _dur, c == null ? 'Duration' : 'Moving time', keyboard: TextInputType.datetime, hint: 'mm:ss or h:mm:ss'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(pace == null ? 'Pace: -' : 'Pace: ${formatPace(pace)} min/km', style: Theme.of(context).textTheme.titleMedium),
              ),
              _field('avgHr', _hr, 'Average HR (optional)', keyboard: TextInputType.number),
              if (_type == 'treadmill') _field('incline', _incline, 'Incline % (optional)'),
              if (_type == 'treadmill' && c != null) ...[
                _field('steps', _steps, 'Steps (optional)', keyboard: TextInputType.number),
                _field('calories', _calories, 'Calories (optional)', keyboard: TextInputType.number),
              ],
              _field('rpe', _rpe, 'RPE 1-10 (optional)', keyboard: TextInputType.number),
              _field('notes', _notes, 'Notes (optional)', keyboard: TextInputType.multiline),
            ],
          ),
        ),
      ),
    );
  }
}
