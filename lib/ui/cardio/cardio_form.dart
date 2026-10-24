import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';

/// New or edit cardio session. Pace updates as distance and duration are typed.
class CardioForm extends StatefulWidget {
  const CardioForm({super.key, required this.store, this.existing});

  final CardioStore store;
  final CardioData? existing;

  @override
  State<CardioForm> createState() => _CardioFormState();
}

class _CardioFormState extends State<CardioForm> {
  late final c = widget.existing;
  late String? _type = c?.type ?? 'run';
  late DateTime _at = c?.startedAt ?? DateTime.now();
  late final _km = TextEditingController(text: c == null ? '' : _num(c!.distanceKm));
  late final _dur = TextEditingController(text: c == null ? '' : _hms(c!.durationSec));
  late final _hr = TextEditingController(text: c?.avgHr?.toString() ?? '');
  late final _incline = TextEditingController(text: c?.inclinePct == null ? '' : _num(c!.inclinePct!));
  late final _rpe = TextEditingController(text: c?.rpe?.toString() ?? '');
  late final _notes = TextEditingController(text: c?.notes ?? '');
  Map<String, String> _errors = {};

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  static String _hms(int s) {
    String two(int n) => n.toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}' : '${s ~/ 60}:${two(s % 60)}';
  }

  @override
  void dispose() {
    for (final t in [_km, _dur, _hr, _incline, _rpe, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _at, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute));
  }

  Future<void> _save() async {
    final errors = validateCardio(
        type: _type, distance: _km.text, duration: _dur.text, avgHr: _hr.text, incline: _incline.text, rpe: _rpe.text);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    String? opt(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();
    await widget.store.save(
      id: c?.id,
      type: _type!,
      startedAt: _at,
      distanceKm: parseNum(_km.text)!,
      durationSec: parseDuration(_dur.text)!,
      avgHr: opt(_hr) == null ? null : int.parse(opt(_hr)!),
      inclinePct: opt(_incline) == null ? null : parseNum(_incline.text),
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
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: label, hintText: hint, errorText: _errors[key], border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final km = parseNum(_km.text), sec = parseDuration(_dur.text);
    final pace = km == null || sec == null ? null : paceSecPerKm(km, sec);
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Log cardio' : 'Edit cardio'),
        actions: [
          if (c != null) IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: _delete),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.check), label: const Text('Save'), onPressed: _save),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              SegmentedButton<String>(
                segments: [for (final t in cardioTypes) ButtonSegment(value: t, label: Text(t[0].toUpperCase() + t.substring(1)))],
                selected: {?_type},
                onSelectionChanged: (s) => setState(() => _type = s.single),
              ),
              if (_errors['type'] case final e?) Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text('${loc.formatMediumDate(_at)}, ${TimeOfDay.fromDateTime(_at).format(context)}'),
                onTap: _pickDate,
              ),
              _field('distance', _km, 'Distance (km)'),
              _field('duration', _dur, 'Duration', keyboard: TextInputType.datetime, hint: 'mm:ss or h:mm:ss'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(pace == null ? 'Pace: -' : 'Pace: ${formatPace(pace)} min/km',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              _field('avgHr', _hr, 'Average HR (optional)', keyboard: TextInputType.number),
              _field('incline', _incline, 'Incline % (optional)'),
              _field('rpe', _rpe, 'RPE 1-10 (optional)', keyboard: TextInputType.number),
              _field('notes', _notes, 'Notes (optional)', keyboard: TextInputType.multiline),
            ],
          ),
        ),
      ),
    );
  }
}
