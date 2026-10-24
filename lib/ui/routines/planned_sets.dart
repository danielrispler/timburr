import 'package:flutter/material.dart';

import '../../data/cardio.dart' show parseNum;
import '../../data/catalog.dart';
import '../../data/routines.dart';
import '../core/theme.dart';
import '../exercises/exercise_image.dart';

/// One exercise of a saved workout: photo, instructions and its planned sets. Saves on "Save".
class PlannedSetsEditor extends StatefulWidget {
  const PlannedSetsEditor({super.key, required this.store, required this.entry, required this.routineExerciseId});

  final RoutineStore store;
  final CatalogEntry entry;
  final String routineExerciseId;

  @override
  State<PlannedSetsEditor> createState() => _PlannedSetsEditorState();
}

class _PlannedSetsEditorState extends State<PlannedSetsEditor> {
  // One (reps or seconds, kg) controller pair per set.
  List<(TextEditingController, TextEditingController)>? _sets;
  bool get _timed => widget.entry.loadType == 'timed';

  @override
  void initState() {
    super.initState();
    widget.store.watchSets(widget.routineExerciseId).first.then((sets) {
      if (!mounted) return;
      setState(() => _sets = [
            for (final s in sets) _pair((_timed ? s.durationSec : s.reps)?.toString() ?? '', s.weightKg),
          ]);
    });
  }

  (TextEditingController, TextEditingController) _pair(String count, double? kg) => (
        TextEditingController(text: count),
        TextEditingController(text: kg == null ? '' : (kg == kg.roundToDouble() ? kg.toInt() : kg).toString()),
      );

  @override
  void dispose() {
    for (final (a, b) in _sets ?? const <(TextEditingController, TextEditingController)>[]) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await widget.store.saveSets(widget.routineExerciseId, [
      for (final (count, kg) in _sets!)
        (
          weightKg: parseNum(kg.text),
          reps: _timed ? null : int.tryParse(count.text.trim()),
          durationSec: _timed ? int.tryParse(count.text.trim()) : null,
        ),
    ]);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    await widget.store.remove(widget.routineExerciseId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry, sets = _sets;
    final kgLabel = e.loadType == 'bodyweight' ? 'Added kg' : 'Total weight';
    return Scaffold(
      appBar: AppBar(actions: [IconButton(icon: const Icon(Icons.delete), tooltip: 'Remove exercise', onPressed: _remove)]),
      bottomNavigationBar: BottomAction(children: [FilledButton(onPressed: sets == null ? null : _save, child: const Text('Save'))]),
      body: sets == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                  ExerciseHero(e),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(e.name, style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  if (e.equipment != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(e.equipment!)),
                  if (e.instructions.isNotEmpty)
                    ExpansionTile(title: const Text('Instructions'), children: [
                      for (final (i, step) in e.instructions.indexed) ListTile(dense: true, title: Text('${i + 1}. $step')),
                    ]),
                  for (final (i, (count, kg)) in sets.indexed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Set ${i + 1}', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: count,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: _timed ? 'Seconds' : 'Reps'),
                            ),
                          ),
                          if (!_timed) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: kg,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: kgLabel, hintText: 'Last time'),
                              ),
                            ),
                          ],
                        ]),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.remove),
                          label: const Text('Delete set'),
                          onPressed: sets.isEmpty ? null : () => setState(() => sets.removeLast()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add set'),
                          onPressed: () => setState(() => sets.add(sets.isEmpty
                              ? _pair(_timed ? '30' : '10', null)
                              : _pair(sets.last.$1.text, parseNum(sets.last.$2.text)))),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
    );
  }
}
