import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

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
    this.aliases = const [],
    this.media,
    this.loadType,
    this.stickyNote,
    this.lastRestSec,
  });

  final String name;
  final String? libraryId, rowId, category, equipment, loadType, stickyNote;

  /// Gym visual media file stem of a library exercise, for [exerciseMediaUrl].
  final String? media;
  final List<String> muscles, secondaryMuscles, instructions;

  /// Other names for a library exercise, such as the gym's name for it.
  final List<String> aliases;

  /// [name] with its aliases in brackets.
  String get label => aliases.isEmpty ? name : '$name (${aliases.join(', ')})';
  final int? lastRestSec;
}

/// Library plus `exercises` rows, with search and filters.
class Catalog {
  Catalog(this._db, [Future<String> Function()? loadLibrary])
    : _loadLibrary = loadLibrary ?? (() => rootBundle.loadString('assets/exercises.json'));

  final AppDb _db;
  AppDb get db => _db;
  final Future<String> Function() _loadLibrary;
  Map<String, CatalogEntry>? _library;

  /// Library ids from the previous bundled library, mapped to their current ids.
  final Map<String, String> _legacy = {};

  /// Filter options seen in the last [list] call (unfiltered entries).
  List<String> muscles = [], equipment = [];

  Future<List<CatalogEntry>> list({String query = '', String? muscle, String? equipment}) async {
    final all = _merge(
      await _libraryEntries(),
      await (_db.select(_db.exercises)..where((e) => e.deletedAt.isNull())).get(),
      _legacy,
    );
    muscles = (<String>{
      for (final e in all) ...[...e.muscles, ...e.secondaryMuscles],
    }.toList()..sort());
    this.equipment = ({for (final e in all) ?e.equipment}.toList()..sort());
    final q = query.trim().toLowerCase();
    return [
      for (final e in all)
        if (e.label.toLowerCase().contains(q) &&
            (muscle == null || e.muscles.contains(muscle) || e.secondaryMuscles.contains(muscle)) &&
            (equipment == null || e.equipment == equipment))
          e,
    ];
  }

  /// Row id for [entry]. A library entry without a row gets one with id [libraryRowId];
  /// an existing row is left untouched, so picking it does not re-dirty it.
  Future<String> rowIdFor(CatalogEntry entry) async => entry.rowId ?? await configureLibrary(entry.libraryId!);

  /// Get-or-create the row for a library exercise, applying any given overrides. Returns its id.
  /// With no overrides, an existing row is not rewritten. Pass the entry's [rowId] when it has one:
  /// a row logged under a legacy library id keeps its own id.
  Future<String> configureLibrary(String libraryId, {String? rowId, String? loadType, String? stickyNote}) async {
    final id = rowId ?? libraryRowId(libraryId);
    if (loadType == null && stickyNote == null &&
        await (_db.select(_db.exercises)..where((e) => e.id.equals(id))).getSingleOrNull() != null) {
      return id;
    }
    await _db.save(_db.exercises, {
      'id': id,
      'library_id': libraryId,
      'load_type': ?loadType,
      'sticky_note': ?stickyNote,
    });
    return id;
  }

  /// Creates (no [id]) or edits a custom exercise. Returns its id.
  Future<String> saveCustom({
    String? id,
    required String name,
    required String loadType,
    List<String> muscles = const [],
    String? equipment,
  }) async {
    id ??= const Uuid().v4();
    await _db.save(_db.exercises, {
      'id': id,
      'name': name,
      'load_type': loadType,
      'muscles': muscles,
      'equipment': equipment,
    });
    return id;
  }

  Future<void> setStickyNote(String rowId, String? note) => _db.save(_db.exercises, {'id': rowId, 'sticky_note': note});

  Future<void> setLastRest(String rowId, int sec) => _db.save(_db.exercises, {'id': rowId, 'last_rest_sec': sec});

  Future<void> deleteCustom(String rowId) => _db.save(_db.exercises, {'id': rowId, 'deleted_at': DateTime.now()});

  /// Resolves a row by id, deleted or not, so history keeps its names.
  Future<CatalogEntry?> byId(String rowId) async {
    final row = await (_db.select(_db.exercises)..where((e) => e.id.equals(rowId))).getSingleOrNull();
    return row == null ? null : _entry(await _libraryEntries(), row, _legacy);
  }

  Future<Map<String, CatalogEntry>> _libraryEntries() async {
    if (_library case final l?) return l;
    final list = (jsonDecode(await _loadLibrary()) as List).cast<Map<String, dynamic>>();
    for (final m in list) {
      for (final old in (m['legacyIds'] as List?)?.cast<String>() ?? const <String>[]) {
        _legacy[old] = m['id'] as String;
      }
    }
    return _library = {
      for (final m in list)
        m['id'] as String: CatalogEntry(
          libraryId: m['id'] as String,
          name: m['name'] as String,
          category: m['category'] as String?,
          equipment: m['equipment'] as String?,
          muscles: (m['primaryMuscles'] as List).cast(),
          secondaryMuscles: (m['secondaryMuscles'] as List).cast(),
          instructions: (m['instructions'] as List).cast(),
          aliases: (m['aliases'] as List?)?.cast() ?? const [],
          media: m['media'] as String?,
          loadType: const {'body only', 'body weight'}.contains(m['equipment']) ? 'bodyweight' : 'weighted',
        ),
    };
  }
}

List<CatalogEntry> _merge(Map<String, CatalogEntry> library, List<Exercise> rows, Map<String, String> legacy) {
  final merged = {...library};
  for (final r in rows) {
    merged[legacy[r.libraryId] ?? r.libraryId ?? r.id] = _entry(library, r, legacy);
  }
  return merged.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

CatalogEntry _entry(Map<String, CatalogEntry> library, Exercise r, Map<String, String> legacy) {
  final libraryId = legacy[r.libraryId] ?? r.libraryId;
  final lib = libraryId == null ? null : library[libraryId];
  return CatalogEntry(
    rowId: r.id,
    libraryId: libraryId,
    name: r.name ?? lib?.name ?? humanize(r.libraryId!),
    category: lib?.category,
    equipment: r.equipment ?? lib?.equipment,
    muscles: r.muscles.isNotEmpty ? r.muscles : lib?.muscles ?? const [],
    secondaryMuscles: lib?.secondaryMuscles ?? const [],
    instructions: lib?.instructions ?? const [],
    aliases: r.name == null ? lib?.aliases ?? const [] : const [],
    media: lib?.media,
    loadType: r.loadType ?? lib?.loadType ?? 'weighted',
    stickyNote: r.stickyNote,
    lastRestSec: r.lastRestSec,
  );
}

/// Fixed forever: changing it re-keys every library row (#1). No user_id in the name.
const _libraryNamespace = '3f1c2b7e-8d4a-5c6f-9e0b-1a2d3c4e5f60';

/// Deterministic row id for a library exercise, so two stores agree.
String libraryRowId(String libraryId) => const Uuid().v5(_libraryNamespace, libraryId);

/// `Old_Cable_Fly-Low` -> `Old Cable Fly Low`, for rows whose library entry left the bundle.
String humanize(String libraryId) => libraryId.split(RegExp(r'[_\-\s]+')).where((w) => w.isNotEmpty).join(' ');

/// Gym visual media of a library exercise: the 180 px thumbnail, or the animated GIF when [gif].
Uri exerciseMediaUrl(String media, {bool gif = false}) => Uri.https('raw.githubusercontent.com',
    '/hasaneyldrm/exercises-dataset/$_mediaCommit/${gif ? 'videos/$media.gif' : 'images/$media.jpg'}');

/// Pinned like scripts/build-exercises.mjs, so a file renamed upstream doesn't break the bundled list.
const _mediaCommit = '7455efae41b330c265e7cd4b78dfa848e7ce5ebd';

/// YouTube search for how to do [name].
Uri youtubeSearchUrl(String name) => Uri.https('www.youtube.com', '/results', {'search_query': '$name exercise'});
