import 'package:flutter/material.dart';

import '../../data/catalog.dart';

/// Search plus muscle and equipment filters over the catalog. Reused by later tickets to pick an exercise.
class ExercisePicker extends StatefulWidget {
  const ExercisePicker({super.key, required this.catalog, required this.onSelected});

  final Catalog catalog;
  final ValueChanged<CatalogEntry> onSelected;

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
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
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
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Search exercises', border: OutlineInputBorder()),
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
            Expanded(
              child: entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? const Center(child: Text('No exercises match'))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (_, i) {
                            final e = entries[i];
                            return ListTile(
                              title: Text(e.name),
                              subtitle: Text([...e.muscles, ?e.equipment].join(' · ')),
                              onTap: () => widget.onSelected(e),
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
