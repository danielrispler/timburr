import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'db.dart';

const _uuid = Uuid();
const cardioTypes = ['run', 'walk', 'treadmill', 'bike'];

/// Short v1 description for the chat assistant; see docs/import-format.md.
const importFormat = '''
Turn my workout screenshot into JSON in this exact format (version 1). Output only the JSON.
{
  "version": 1,
  "workouts": [
    {
      "date": "2026-10-24T16:13",
      "routine": "Push A",
      "notes": "",
      "exercises": [
        {
          "name": "Barbell Bench Press - Medium Grip",
          "notes": "",
          "supersetWithNext": false,
          "sets": [{ "weightKg": 70, "reps": 10 }, { "weightKg": 80, "reps": 8 }]
        }
      ]
    }
  ],
  "cardio": [
    { "type": "run", "date": "2026-10-23T17:15", "distanceKm": 5.0, "durationSec": 1680,
      "avgHr": 158, "inclinePct": null, "rpe": 7, "notes": "" }
  ]
}
Rules: dates are local time. For bodyweight sets weightKg is the added weight (or null). Timed sets use "durationSec" instead of "reps". "routine", "notes", "supersetWithNext", "avgHr", "inclinePct" and "rpe" are optional. Cardio type is one of run, walk, treadmill, bike; rpe is 1-10. Use my exercise names below when they match.''';

/// Every problem in [data] as `path: message`; empty means valid v1.
List<String> validateImport(Object? data) {
  final errors = <String>[];
  void err(String path, String msg) => errors.add('$path: $msg');

  String at(String path, String key) => path.isEmpty ? key : '$path.$key';

  void fields(Map m, String path, Set<String> allowed) {
    for (final k in m.keys) {
      if (!allowed.contains(k)) err(at(path, '$k'), 'unknown field');
    }
  }

  void str(Map m, String path, String key, {bool required = false}) {
    final v = m[key];
    if (required ? (v is! String || v.trim().isEmpty) : (v != null && v is! String)) {
      err('$path.$key', required ? 'required' : 'must be text');
    }
  }

  void date(Map m, String path) {
    final v = m['date'];
    if (v is! String || DateTime.tryParse(v) == null) err('$path.date', 'must be a date like 2026-10-24T16:13');
  }

  void whole(Map m, String path, String key, {int min = 0, int? max, bool required = false}) {
    final v = m[key];
    if (v == null && !required) return;
    if (v is! int || v < min || (max != null && v > max)) {
      err('$path.$key', max != null ? 'must be a whole number $min-$max' : 'must be a whole number >= $min');
    }
  }

  void number(Map m, String path, String key, {bool positive = false, bool required = false}) {
    final v = m[key];
    if (v == null && !required) return;
    if (v is! num || (positive ? v <= 0 : v < 0)) err('$path.$key', 'must be a number ${positive ? '> 0' : '>= 0'}');
  }

  List? list(Map m, String path, String key, {bool nonEmpty = false}) {
    final v = m[key];
    if (v == null && !nonEmpty) return const [];
    if (v is! List || (nonEmpty && v.isEmpty)) {
      err(at(path, key), nonEmpty ? 'must be a non-empty list' : 'must be a list');
      return null;
    }
    return v;
  }

  if (data is! Map) return ['root: must be an object'];
  fields(data, '', {'version', 'workouts', 'cardio'});
  if (data['version'] != 1) err('version', 'must be 1');

  for (final (i, w) in (list(data, '', 'workouts')?.indexed ?? const <(int, dynamic)>[])) {
    final p = 'workouts[$i]';
    if (w is! Map) {
      err(p, 'must be an object');
      continue;
    }
    fields(w, p, {'date', 'routine', 'notes', 'exercises'});
    date(w, p);
    str(w, p, 'routine');
    str(w, p, 'notes');
    for (final (j, e) in (list(w, p, 'exercises', nonEmpty: true)?.indexed ?? const <(int, dynamic)>[])) {
      final pe = '$p.exercises[$j]';
      if (e is! Map) {
        err(pe, 'must be an object');
        continue;
      }
      fields(e, pe, {'name', 'notes', 'supersetWithNext', 'sets'});
      str(e, pe, 'name', required: true);
      str(e, pe, 'notes');
      if (e['supersetWithNext'] != null && e['supersetWithNext'] is! bool) err('$pe.supersetWithNext', 'must be true or false');
      for (final (k, s) in (list(e, pe, 'sets', nonEmpty: true)?.indexed ?? const <(int, dynamic)>[])) {
        final ps = '$pe.sets[$k]';
        if (s is! Map) {
          err(ps, 'must be an object');
          continue;
        }
        fields(s, ps, {'weightKg', 'reps', 'durationSec'});
        number(s, ps, 'weightKg');
        whole(s, ps, 'reps');
        whole(s, ps, 'durationSec');
        if ((s['reps'] == null) == (s['durationSec'] == null)) err(ps, 'give reps or durationSec, not both');
      }
    }
  }

  for (final (i, c) in (list(data, '', 'cardio')?.indexed ?? const <(int, dynamic)>[])) {
    final p = 'cardio[$i]';
    if (c is! Map) {
      err(p, 'must be an object');
      continue;
    }
    fields(c, p, {'type', 'date', 'distanceKm', 'durationSec', 'avgHr', 'inclinePct', 'rpe', 'notes'});
    if (!cardioTypes.contains(c['type'])) err('$p.type', 'must be one of ${cardioTypes.join(', ')}');
    date(c, p);
    number(c, p, 'distanceKm', positive: true, required: true);
    whole(c, p, 'durationSec', min: 1, required: true);
    whole(c, p, 'avgHr', min: 1);
    if (c['inclinePct'] != null && c['inclinePct'] is! num) err('$p.inclinePct', 'must be a number');
    whole(c, p, 'rpe', min: 1, max: 10);
    str(c, p, 'notes');
  }
  return errors;
}

/// Imports a validated v1 document into the local store in one transaction.
class Importer {
  Importer(this._db, this._catalog);
  final AppDb _db;
  final Catalog _catalog;

  /// [importFormat] plus custom exercises and exercises used at least once.
  Future<String> formatText() async {
    final custom = await (_db.select(_db.exercises)..where((e) => e.libraryId.isNull() & e.deletedAt.isNull())).get();
    final used = await (_db.selectOnly(_db.workoutExercises, distinct: true)
          ..addColumns([_db.workoutExercises.exerciseId])
          ..where(_db.workoutExercises.deletedAt.isNull()))
        .map((r) => r.read(_db.workoutExercises.exerciseId)!)
        .get();
    final names = <String>{
      for (final id in {...custom.map((e) => e.id), ...used}) ?(await _catalog.byId(id))?.name,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return '$importFormat\n\nMy exercises:\n${names.map((n) => '- $n').join('\n')}\n';
  }

  /// Lower-cased name to row id or library entry, for every catalog exercise.
  Future<Map<String, CatalogEntry>> _byName() async =>
      {for (final e in (await _catalog.list()).reversed) e.name.toLowerCase(): e};

  /// Exercise names in [data] not found in the catalog, first spelling kept, in order.
  Future<List<String>> unknownNames(Map data) async {
    final known = await _byName();
    final seen = <String, String>{};
    for (final w in data['workouts'] as List? ?? const []) {
      for (final e in w['exercises'] as List) {
        final n = (e['name'] as String).trim();
        if (!known.containsKey(n.toLowerCase())) seen.putIfAbsent(n.toLowerCase(), () => n);
      }
    }
    return seen.values.toList();
  }

  /// Saves [data] atomically. [mapping] sends a lower-cased unknown name to an existing exercise;
  /// unmapped unknowns become custom exercises. Throws [FormatException] if [data] is invalid.
  Future<void> save(Map data, {Map<String, CatalogEntry> mapping = const {}}) async {
    final errors = validateImport(data);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    final known = await _byName();
    final routines = {
      for (final r in await (_db.select(_db.routines)..where((r) => r.deletedAt.isNull())).get()) r.name.toLowerCase(): r.id,
    };
    await _db.transaction(() async {
      final created = <String, String>{};
      Future<String> exerciseId(Map e) async {
        final name = (e['name'] as String).trim(), key = name.toLowerCase();
        if ((mapping[key] ?? known[key]) case final entry?) {
          return entry.rowId ?? await _catalog.configureLibrary(entry.libraryId!);
        }
        final sets = (e['sets'] as List).cast<Map>();
        return created[key] ??= await _catalog.saveCustom(
          name: name,
          loadType: sets.any((s) => s['durationSec'] != null)
              ? 'timed'
              : sets.every((s) => s['weightKg'] == null)
                  ? 'bodyweight'
                  : 'weighted',
        );
      }

      for (final w in data['workouts'] as List? ?? const []) {
        final id = _uuid.v4(), at = DateTime.parse(w['date'] as String);
        await _db.save(_db.workouts, {
          'id': id,
          'routine_id': routines[(w['routine'] as String?)?.trim().toLowerCase()],
          'started_at': at,
          'finished_at': at, // shortcut: duration unknown from a screenshot, so 0; add an end time to v2 if wanted
          'notes': _blank(w['notes']),
        });
        for (final (i, e) in (w['exercises'] as List).indexed) {
          final weId = _uuid.v4();
          await _db.save(_db.workoutExercises, {
            'id': weId,
            'workout_id': id,
            'exercise_id': await exerciseId(e as Map),
            'position': i,
            'notes': _blank(e['notes']),
            'superset_with_next': e['supersetWithNext'] ?? false,
          });
          for (final (k, s) in (e['sets'] as List).indexed) {
            await _db.save(_db.workoutSets, {
              'id': _uuid.v4(),
              'workout_exercise_id': weId,
              'set_number': k + 1,
              'weight_kg': (s['weightKg'] as num?)?.toDouble(),
              'reps': s['reps'],
              'duration_sec': s['durationSec'],
              'done': true,
            });
          }
        }
      }
      for (final c in data['cardio'] as List? ?? const []) {
        await _db.save(_db.cardio, {
          'id': _uuid.v4(),
          'type': c['type'],
          'started_at': DateTime.parse(c['date'] as String),
          'distance_km': (c['distanceKm'] as num).toDouble(),
          'duration_sec': c['durationSec'],
          'avg_hr': c['avgHr'],
          'incline_pct': (c['inclinePct'] as num?)?.toDouble(),
          'rpe': c['rpe'],
          'notes': _blank(c['notes']),
        });
      }
    });
  }
}

String? _blank(Object? s) => s is String && s.trim().isNotEmpty ? s : null;
