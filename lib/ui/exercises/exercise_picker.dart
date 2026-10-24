import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../core/theme.dart';
import 'exercise_image.dart';

/// Search plus muscle and equipment filters over the catalog. Reused by later tickets to pick an exercise.
class ExercisePicker extends StatefulWidget {
  const ExercisePicker({super.key, required this.catalog, required this.onSelected, this.onCreate, this.onAdd});

  final Catalog catalog;
  /// Awaited, then the list reloads, so edits made on a pushed page show up.
  final FutureOr<void> Function(CatalogEntry) onSelected;
  final Future<void> Function()? onCreate;

  /// Set for multi-select: rows get checkboxes and an "Add" button passes the ticked entries, in tick order.
  final void Function(List<CatalogEntry>)? onAdd;

  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  String _query = '';
  String? _muscle, _equipment;
  List<CatalogEntry>? _entries;
  final _ticked = <String, CatalogEntry>{}; // by libraryId ?? rowId

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.catalog.list(query: _query, muscle: _muscle, equipment: _equipment);
    if (mounted) setState(() => _entries = entries);
  }

  /// Outlined chip with a drop-down arrow, as in Google Health. '' in the menu means "Any".
  Widget _filter(String label, String? value, List<String> options, ValueChanged<String?> onChanged) =>
      PopupMenuButton<String>(
        tooltip: label,
        onSelected: (v) {
          onChanged(v.isEmpty ? null : v);
          _reload();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('Any')),
          for (final o in options) PopupMenuItem(value: o, child: Text(o)),
        ],
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(
            color: value == null ? null : Theme.of(context).colorScheme.secondaryContainer,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(value ?? label, style: const TextStyle(fontSize: 15)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                leading: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.search)),
                hintText: 'Search exercises',
                onChanged: (v) {
                  _query = v;
                  _reload();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _filter('Equipment', _equipment, widget.catalog.equipment, (v) => _equipment = v),
                const SizedBox(width: 8),
                _filter('Muscle group', _muscle, widget.catalog.muscles, (v) => _muscle = v),
              ]),
            ),
            if (widget.onCreate case final create?)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New custom exercise'),
                  onPressed: () async {
                    await create();
                    _reload();
                  },
                ),
              ),
            Expanded(
              child: entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? const Center(child: Text('No exercises match'))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (_, i) {
                            final e = entries[i];
                            final key = e.libraryId ?? e.rowId!;
                            return Padding(
                              padding: EdgeInsets.fromLTRB(16, i == 0 ? 8 : 0, 16, 0),
                              child: groupedTile(
                                i,
                                entries.length,
                                ListTile(
                                  leading: ExerciseThumb(e),
                                  title: Text(e.label),
                                  subtitle: Text([...e.muscles, ?e.equipment].join(' · ')),
                                  trailing: widget.onAdd == null
                                      ? null
                                      : Checkbox(
                                          value: _ticked.containsKey(key),
                                          onChanged: (v) => setState(() => v! ? _ticked[key] = e : _ticked.remove(key)),
                                        ),
                                  onTap: widget.onAdd != null
                                      ? () => setState(() => _ticked.remove(key) ?? (_ticked[key] = e))
                                      : () async {
                                    await widget.onSelected(e);
                                    _reload();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
            if (widget.onAdd case final add? when _ticked.isNotEmpty)
              BottomAction(children: [
                FilledButton(onPressed: () => add(_ticked.values.toList()), child: Text('Add ${_ticked.length}')),
              ]),
          ],
        ),
      ),
    );
  }
}
