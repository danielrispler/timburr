import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'db.dart';

/// One browsable exercise: a bundled library entry merged with its `exercises` row, or a custom row.
class CatalogEntry {
  CatalogEntry({
    required this.name,
    this.libraryId,
    this.rowId,
    this.category,
    this.equipment,
    this.muscles = const [],
    this.secondaryMuscles = const [],
    this.instructions = const [],
    this.loadType,
    this.stickyNote,
  });

  final String name;
  final String? libraryId, rowId, category, equipment, loadType, stickyNote;
  final List<String> muscles, secondaryMuscles, instructions;
}

/// Library plus `exercises` rows, with search and filters.
class Catalog {
  Catalog(this._db, [Future<String> Function()? loadLibrary])
      : _loadLibrary = loadLibrary ?? (() => rootBundle.loadString('assets/exercises.json'));

  final AppDb _db;
  final Future<String> Function() _loadLibrary;
  Map<String, CatalogEntry>? _library;

  /// Filter options seen in the last [list] call (unfiltered entries).
  List<String> muscles = [], equipment = [];

  Future<List<CatalogEntry>> list({String query = '', String? muscle, String? equipment}) async {
    final all = _merge(await _libraryEntries(), await (_db.select(_db.exercises)..where((e) => e.deletedAt.isNull())).get());
    muscles = (<String>{for (final e in all) ...[...e.muscles, ...e.secondaryMuscles]}.toList()..sort());
    this.equipment = ({for (final e in all) ?e.equipment}.toList()..sort());
    final q = query.trim().toLowerCase();
    return [
      for (final e in all)
        if (e.name.toLowerCase().contains(q) &&
            (muscle == null || e.muscles.contains(muscle) || e.secondaryMuscles.contains(muscle)) &&
            (equipment == null || e.equipment == equipment))
          e,
    ];
  }

  Future<Map<String, CatalogEntry>> _libraryEntries() async => _library ??= {
        for (final m in (jsonDecode(await _loadLibrary()) as List).cast<Map<String, dynamic>>())
          m['id'] as String: CatalogEntry(
            libraryId: m['id'] as String,
            name: m['name'] as String,
            category: m['category'] as String?,
            equipment: m['equipment'] as String?,
            muscles: (m['primaryMuscles'] as List).cast(),
            secondaryMuscles: (m['secondaryMuscles'] as List).cast(),
            instructions: (m['instructions'] as List).cast(),
            loadType: m['equipment'] == 'body only' ? 'bodyweight' : 'weighted',
          ),
      };
}

List<CatalogEntry> _merge(Map<String, CatalogEntry> library, List<Exercise> rows) {
  final merged = {...library};
  for (final r in rows) {
    final lib = r.libraryId == null ? null : library[r.libraryId];
    merged[r.libraryId ?? r.id] = CatalogEntry(
      rowId: r.id,
      libraryId: r.libraryId,
      name: r.name ?? lib?.name ?? humanize(r.libraryId!),
      category: lib?.category,
      equipment: r.equipment ?? lib?.equipment,
      muscles: r.muscles.isNotEmpty ? r.muscles : lib?.muscles ?? const [],
      secondaryMuscles: lib?.secondaryMuscles ?? const [],
      instructions: lib?.instructions ?? const [],
      loadType: r.loadType ?? lib?.loadType ?? 'weighted',
      stickyNote: r.stickyNote,
    );
  }
  return merged.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// `Old_Cable_Fly-Low` -> `Old Cable Fly Low`, for rows whose library entry left the bundle.
String humanize(String libraryId) => libraryId.split(RegExp(r'[_\-\s]+')).where((w) => w.isNotEmpty).join(' ');
