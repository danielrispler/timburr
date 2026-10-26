import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/db.dart';
import '../../data/health.dart';
import '../../data/workouts.dart';
import '../../data/error_log.dart';

/// Optional Google Health stats for a strength workout: read from a screenshot, checked, then saved.
Future<void> editHealth(BuildContext context, WorkoutStore store, Workout w) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _HealthSheet(store: store, workout: w),
);

/// One-line summary, e.g. "91 bpm • 255 cal • 1:01:29 • effort 5 • load 5"; null when nothing is set.
String? healthSummary(Workout w) {
  final d = w.activeSec;
  final parts = [
    if (w.avgHr != null) '${w.avgHr} bpm',
    if (w.calories != null) '${w.calories} cal',
    if (d != null) '${d ~/ 3600}:${(d ~/ 60 % 60).toString().padLeft(2, '0')}:${(d % 60).toString().padLeft(2, '0')}',
    if (w.effort != null) 'effort ${w.effort}',
    if (w.cardioLoad != null) 'load ${w.cardioLoad}',
  ];
  return parts.isEmpty ? null : parts.join(' • ');
}

class _HealthSheet extends StatefulWidget {
  const _HealthSheet({required this.store, required this.workout});

  final WorkoutStore store;
  final Workout workout;

  @override
  State<_HealthSheet> createState() => _HealthSheetState();
}

class _HealthSheetState extends State<_HealthSheet> {
  late final _hr = _ctrl(widget.workout.avgHr), _cal = _ctrl(widget.workout.calories);
  late final _min = _ctrl(widget.workout.activeSec == null ? null : (widget.workout.activeSec! / 60).round());
  late final _effort = _ctrl(widget.workout.effort), _load = _ctrl(widget.workout.cardioLoad);
  bool _reading = false;
  late int? _sec = widget.workout.activeSec; // exact seconds behind the minutes field
  String? _error;

  TextEditingController _ctrl(int? v) => TextEditingController(text: v?.toString() ?? '');

  @override
  void dispose() {
    for (final c in [_hr, _cal, _min, _effort, _load]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fromScreenshot() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _reading = true);
    final recognizer = TextRecognizer();
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final h = parseHealth([
        for (final b in text.blocks)
          for (final l in b.lines)
            (text: l.text, left: l.boundingBox.left, top: l.boundingBox.top, bottom: l.boundingBox.bottom),
      ]);
      void put(TextEditingController c, int? v) => v == null ? null : c.text = '$v';
      put(_hr, h.avgHr);
      put(_cal, h.calories);
      put(_min, h.activeSec == null ? null : (h.activeSec! / 60).round());
      _sec = h.activeSec ?? _sec;
      put(_effort, h.effort);
      put(_load, h.cardioLoad);
      _error = [h.avgHr, h.calories, h.activeSec, h.effort, h.cardioLoad].every((v) => v == null)
          ? 'No Google Health numbers found in that image'
          : null;
    } catch (e, st) {
      reportError('health_ocr', e, st);
      _error = 'Could not read that image: $e';
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _reading = false);
    }
  }

  final _fieldErrors = <TextEditingController, String>{};

  Future<void> _save() async {
    final maxes = {_hr: 300, _cal: 20000, _min: 24 * 60, _effort: 10, _load: 1000};
    final parsed = <TextEditingController, int?>{};
    _fieldErrors.clear();
    for (final MapEntry(key: c, value: max) in maxes.entries) {
      final t = c.text.trim();
      final n = int.tryParse(t);
      if (t.isNotEmpty && (n == null || n < 0 || n > max)) _fieldErrors[c] = 'Enter a whole number 0-$max';
      parsed[c] = t.isEmpty ? null : n;
    }
    if (_fieldErrors.isNotEmpty) return setState(() {}); // a typo must never erase a stored value

    final effort = parsed[_effort], hr = parsed[_hr];
    // Minutes typed, so seconds from a screenshot are kept when the minutes still match.
    final min = parsed[_min], was = _sec;
    await widget.store.setHealth(widget.workout.id, (
      avgHr: hr == 0 ? null : hr,
      calories: parsed[_cal],
      activeSec: min == null ? null : (was != null && (was / 60).round() == min ? was : min * 60),
      effort: effort == 0 ? null : effort,
      cardioLoad: parsed[_load],
    ));
    if (mounted) Navigator.pop(context);
  }

  Widget _field(TextEditingController c, String label, {String? suffix}) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        errorText: _fieldErrors[c],
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Google Health stats', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Pick a screenshot of the workout in Google Health. The text is read on the phone, then check the numbers.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: _reading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image),
            label: const Text('Fill from screenshot'),
            onPressed: _reading ? null : _fromScreenshot,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          _field(_hr, 'Average heart rate', suffix: 'bpm'),
          _field(_cal, 'Energy burned', suffix: 'cal'),
          _field(_min, 'Duration', suffix: 'min'),
          _field(_effort, 'Overall effort', suffix: '1-10'),
          _field(_load, 'Cardio load'),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    ),
  );
}
