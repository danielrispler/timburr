import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/db.dart';
import '../../data/health.dart';
import '../../data/workouts.dart';

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
    } catch (e) {
      _error = 'Could not read that image: $e';
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    int? v(TextEditingController c, int max) {
      final n = int.tryParse(c.text.trim());
      return n == null || n < 0 || n > max ? null : n;
    }

    final effort = v(_effort, 10);
    // Minutes typed, so seconds from a screenshot are kept when the minutes still match.
    final min = v(_min, 24 * 60), was = _sec;
    await widget.store.setHealth(widget.workout.id, (
      avgHr: v(_hr, 300) == 0 ? null : v(_hr, 300),
      calories: v(_cal, 20000),
      activeSec: min == null ? null : (was != null && (was / 60).round() == min ? was : min * 60),
      effort: effort == 0 ? null : effort,
      cardioLoad: v(_load, 1000),
    ));
    if (mounted) Navigator.pop(context);
  }

  Widget _field(TextEditingController c, String label) => Expanded(
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Google Health stats', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
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
        Row(children: [_field(_hr, 'Avg HR (bpm)'), const SizedBox(width: 16), _field(_cal, 'Calories')]),
        Row(
          children: [
            _field(_min, 'Duration (min)'),
            const SizedBox(width: 16),
            _field(_effort, 'Effort (1-10)'),
            const SizedBox(width: 16),
            _field(_load, 'Cardio load'),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    ),
  );
}
