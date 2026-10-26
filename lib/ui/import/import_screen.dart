import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/catalog.dart';
import '../../data/importer.dart';
import '../../data/error_log.dart';
import '../core/theme.dart';
import '../exercises/exercise_picker.dart';

/// Paste v1 JSON, fix cells in the preview, map unknown exercises, then save all at once.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.importer, required this.catalog});

  final Importer importer;
  final Catalog catalog;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _paste = TextEditingController();
  Map? _data;
  List<String> _errors = [];
  List<String> _unknown = [];
  final _mapping = <String, CatalogEntry>{};
  bool _busy = false;

  Future<void> _copyFormat() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: await widget.importer.formatText()));
    messenger.showSnackBar(const SnackBar(content: Text('Import format copied')));
  }

  void _check() {
    try {
      final d = jsonDecode(_paste.text);
      _data = d is Map ? d : null;
      _revalidate(d);
    } on FormatException catch (e) {
      setState(() {
        _data = null;
        _errors = ['Not valid JSON: ${e.message}'];
      });
    }
  }

  Future<void> _revalidate([Object? raw]) async {
    final errors = validateImport(raw ?? _data);
    final unknown = errors.isEmpty ? await widget.importer.unknownNames(_data!) : <String>[];
    if (mounted) {
      setState(() {
        _errors = errors;
        _unknown = unknown;
      });
    }
  }

  Future<void> _pickMapping(String name) async {
    final picked = await Navigator.of(context).push<CatalogEntry>(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text('Map "$name"')),
        body: ExercisePicker(catalog: widget.catalog, onSelected: (e) => Navigator.of(ctx).pop(e)),
      ),
    ));
    if (picked != null) setState(() => _mapping[name.toLowerCase()] = picked);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context), nav = Navigator.of(context);
    try {
      await widget.importer.save(_data!, mapping: {
        for (final n in _unknown) n.toLowerCase(): ?_mapping[n.toLowerCase()],
      });
      messenger.showSnackBar(SnackBar(
        content: Text('Imported ${(_data!['workouts'] as List?)?.length ?? 0} workouts, '
            '${(_data!['cardio'] as List?)?.length ?? 0} cardio'),
      ));
      nav.pop();
    } catch (e, st) {
      reportError('import', e, st, {'workouts': (_data!['workouts'] as List?)?.length, 'cardio': (_data!['cardio'] as List?)?.length});
      setState(() => _errors = ['Nothing saved: $e']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// An editable cell bound to `node[key]`. [numeric] cells parse to num; empty means null.
  Widget _cell(Map node, String key, {bool numeric = false, double width = 72}) => SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey((node, key)), // record == compares node by identity, stable across builds
          initialValue: node[key]?.toString() ?? '',
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: const InputDecoration(isDense: true),
          onChanged: (t) {
            final v = t.trim();
            node[key] = v.isEmpty ? null : numeric ? (num.tryParse(v) ?? v) : t;
            _revalidate();
          },
        ),
      );

  Widget _table(List<String> headers, List<List<Widget>> rows) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 12,
          columns: [for (final h in headers) DataColumn(label: Text(h))],
          rows: [for (final r in rows) DataRow(cells: [for (final c in r) DataCell(c)])],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final error = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      bottomNavigationBar: d == null
          ? null
          : BottomAction(children: [
              FilledButton(onPressed: _errors.isEmpty && !_busy ? _save : null, child: const Text('Save all')),
            ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.tonalIcon(
                onPressed: _copyFormat,
                icon: const Icon(Icons.copy),
                label: const Text('Copy import format'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paste,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Paste JSON'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: _check, child: const Text('Check')),
              for (final e in _errors)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(e, style: TextStyle(color: error))),
              if (d != null) ...[
                for (final (i, w) in ((d['workouts'] as List?) ?? const []).indexed)
                  if (w is Map) ...[
                    const SizedBox(height: 16),
                    Text('Workout ${i + 1}', style: Theme.of(context).textTheme.titleMedium),
                    _table(['Date', 'Routine', 'Notes'], [
                      [_cell(w, 'date', width: 150), _cell(w, 'routine', width: 120), _cell(w, 'notes', width: 160)],
                    ]),
                    _table(['Exercise', 'Set', 'kg', 'Reps', 'Sec'], [
                      for (final e in (w['exercises'] as List? ?? const []).whereType<Map>())
                        for (final (k, s) in (e['sets'] as List? ?? const []).whereType<Map>().indexed)
                          [
                            k == 0 ? _cell(e, 'name', width: 200) : const SizedBox(),
                            Text('${k + 1}'),
                            _cell(s, 'weightKg', numeric: true),
                            _cell(s, 'reps', numeric: true),
                            _cell(s, 'durationSec', numeric: true),
                          ],
                    ]),
                  ],
                if ((d['cardio'] as List?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 16),
                  Text('Cardio', style: Theme.of(context).textTheme.titleMedium),
                  _table(['Type', 'Date', 'km', 'Sec', 'HR', 'Incline', 'RPE', 'Notes'], [
                    for (final c in (d['cardio'] as List).whereType<Map>())
                      [
                        _cell(c, 'type', width: 90),
                        _cell(c, 'date', width: 150),
                        _cell(c, 'distanceKm', numeric: true),
                        _cell(c, 'durationSec', numeric: true),
                        _cell(c, 'avgHr', numeric: true),
                        _cell(c, 'inclinePct', numeric: true),
                        _cell(c, 'rpe', numeric: true),
                        _cell(c, 'notes', width: 160),
                      ],
                  ]),
                ],
                if (_unknown.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const SectionTitle('Unknown exercises'),
                  for (final (i, n) in _unknown.indexed)
                    groupedTile(i, _unknown.length, ListTile(
                      title: Text(n),
                      subtitle: Text(switch (_mapping[n.toLowerCase()]) {
                        final e? => 'Map to ${e.name}',
                        null => 'Create as a new custom exercise',
                      }),
                      trailing: _mapping.containsKey(n.toLowerCase())
                          ? IconButton(
                              tooltip: 'Create new instead',
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _mapping.remove(n.toLowerCase())),
                            )
                          : const Icon(Icons.edit),
                      onTap: () => _pickMapping(n),
                    )),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
