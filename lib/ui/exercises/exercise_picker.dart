import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../../data/catalog.dart';

/// Search plus muscle and equipment filters over the catalog. Reused by later tickets to pick an exercise.
class ExercisePicker extends StatefulWidget {
  const ExercisePicker({super.key, required this.catalog, required this.onSelected, this.onCreate});

  final Catalog catalog;
  /// Awaited, then the list reloads, so edits made on a pushed page show up.
  final FutureOr<void> Function(CatalogEntry) onSelected;
  final Future<void> Function()? onCreate;

  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  String _query = '';
  String? _muscle, _equipment;
  List<CatalogEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.catalog.list(query: _query, muscle: _muscle, equipment: _equipment);
    if (mounted) setState(() => _entries = entries);
  }

  Widget _filter(String label, String? value, List<String> options, ValueChanged<String?> onChanged) => Expanded(
        child: DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) {
            onChanged(v);
            _reload();
          },
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
                _filter('Muscle', _muscle, widget.catalog.muscles, (v) => _muscle = v),
                const SizedBox(width: 12),
                _filter('Equipment', _equipment, widget.catalog.equipment, (v) => _equipment = v),
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
                            const big = Radius.circular(28), small = Radius.circular(4);
                            // Same look as TileGroup, kept per item so the list stays lazy.
                            return Padding(
                              padding: EdgeInsets.fromLTRB(16, i == 0 ? 8 : 2, 16, 0),
                              child: Material(
                                color: Theme.of(context).colorScheme.surfaceContainer,
                                clipBehavior: Clip.antiAlias,
                                borderRadius: BorderRadius.vertical(
                                    top: i == 0 ? big : small, bottom: i == entries.length - 1 ? big : small),
                                child: ListTile(
                              leading: IconTile(muscleIcon(e.muscles.firstOrNull)),
                              title: Text(e.name),
                              subtitle: Text([...e.muscles, ?e.equipment].join(' · ')),
                              onTap: () async {
                                await widget.onSelected(e);
                                _reload();
                              },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
