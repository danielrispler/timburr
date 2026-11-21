import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'cardio.dart';
import 'catalog.dart';
import 'db.dart';
import 'routines.dart';

const _uuid = Uuid();

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
Rules: dates are local time. For bodyweight sets weightKg is the added weight (or null). Timed sets use "durationSec" instead of "reps". "routine", "notes", "supersetWithNext", "avgHr", "inclinePct" and "rpe" are optional. Cardio type is run or treadmill; rpe is 1-10. Use my exercise names below when they match.''';

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

  void whole(Map m, String path, String key, {int min = 0, int max = int4Max, bool required = false}) {
    final v = m[key];
    if (v == null && !required) return;
    if (v is! int || v < min || v > max) {
      err('$path.$key', max != int4Max ? 'must be a whole number $min-$max' : v is int && v > max ? 'must be at most $max' : 'must be a whole number >= $min');
    }
  }

  /// [below] is the exclusive cap of the server numeric column, e.g. 10000 for numeric(6, 2).
  void number(Map m, String path, String key, {bool positive = false, bool required = false, num? below}) {
    final v = m[key];
    if (v == null && !required) return;
    if (v is! num || (positive ? v <= 0 : v < 0)) {
      err('$path.$key', 'must be a number ${positive ? '> 0' : '>= 0'}');
    } else if (below != null && v >= below) {
      err('$path.$key', 'must be less than $below');
    }
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
        number(s, ps, 'weightKg', below: 10000);
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
    number(c, p, 'distanceKm', positive: true, below: distanceBelow, required: true);
    whole(c, p, 'durationSec', min: 1, required: true);
    whole(c, p, 'avgHr', min: 1);
    if (c['inclinePct'] != null && (c['inclinePct'] is! num || (c['inclinePct'] as num) < 0 || roundTo(c['inclinePct'] as num, 1) > maxIncline)) {
      err('$p.inclinePct', 'must be a number between 0 and $maxIncline');
    }
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

  /// Lower-cased name or alias to row id or library entry, for every catalog exercise. A name beats an alias.
  Future<Map<String, CatalogEntry>> _byName() async {
    final all = (await _catalog.list()).reversed;
    return {
      for (final e in all) for (final a in e.aliases) a.toLowerCase(): e,
      for (final e in all) e.name.toLowerCase(): e,
    };
  }

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
  /// unmapped unknowns become custom exercises. With [saveRoutines], a workout whose "routine" names no live routine
  /// creates that routine, planned from its latest workout's exercises and sets. Throws [FormatException] if [data] is invalid.
  Future<void> save(Map data, {Map<String, CatalogEntry> mapping = const {}, bool saveRoutines = false}) async {
    final errors = validateImport(data);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    final known = await _byName();
    final routines = {
      for (final r in await (_db.select(_db.routines)..where((r) => r.deletedAt.isNull())).get()) r.name.toLowerCase(): r.id,
    };
    await _db.transaction(() async {
      final created = <String, String>{};
      final plannedAt = <String, DateTime>{}; // routine made by this import -> date of the workout it is planned from
      Future<String> exerciseId(Map e) async {
        final name = (e['name'] as String).trim(), key = name.toLowerCase();
        if ((mapping[key] ?? known[key]) case final entry?) {
          return _catalog.rowIdFor(entry);
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
        final id = _uuid.v4(), at = DateTime.parse(w['date'] as String).toLocal(); // stored local, as sync does, so text sort works
        final routineName = (w['routine'] as String?)?.trim() ?? '', key = routineName.toLowerCase();
        if (saveRoutines && routineName.isNotEmpty && !routines.containsKey(key)) {
          routines[key] = await RoutineStore(_db).create(routineName);
          plannedAt[key] = at;
        }
        final Plan? plan = plannedAt.containsKey(key) && !at.isBefore(plannedAt[key]!) ? [] : null;
        if (plan != null) plannedAt[key] = at;
        await _db.save(_db.workouts, {
          'id': id,
          'routine_id': routines[key],
          'started_at': at,
          'finished_at': at, // shortcut: duration unknown from a screenshot, so 0; add an end time to v2 if wanted
          'notes': _blank(w['notes']),
        });
        for (final (i, e) in (w['exercises'] as List).indexed) {
          final weId = _uuid.v4(), exId = await exerciseId(e as Map);
          plan?.add((
            exerciseId: exId,
            alternativeIds: const [],
            sets: [
              for (final s in e['sets'] as List)
                (weightKg: (s['weightKg'] as num?)?.toDouble(), reps: s['reps'] as int?, durationSec: s['durationSec'] as int?)
            ],
          ));
          await _db.save(_db.workoutExercises, {
            'id': weId,
            'workout_id': id,
            'exercise_id': exId,
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
        if (plan != null) await RoutineStore(_db).replacePlan(routines[key]!, plan);
      }
      for (final c in data['cardio'] as List? ?? const []) {
        await _db.save(_db.cardio, {
          'id': _uuid.v4(),
          'type': c['type'],
          'started_at': DateTime.parse(c['date'] as String).toLocal(),
          'distance_km': (c['distanceKm'] as num?)?.toDouble(),
          'duration_sec': c['durationSec'],
          'avg_hr': c['avgHr'],
          'incline_pct': (c['inclinePct'] as num?)?.toDouble(),
          'rpe': c['rpe'],
          'notes': _blank(c['notes']),
        });
      }
    });
  }

  /// Finished, live workouts and live cardio started in [[from], [to]), oldest first, as a v1 document that [save] takes back.
  /// v1 can't express skipped exercises, drop sets, undone sets or sets without reps or time, so they are left out;
  /// then so is an exercise with no sets and a workout with no exercises.
  Future<String> export({DateTime? from, DateTime? to}) async {
    Expression<bool> inRange(GeneratedColumn<DateTime> at) =>
        (from == null ? const Constant(true) : at.isBiggerOrEqualValue(from)) &
        (to == null ? const Constant(true) : at.isSmallerThanValue(to));
    final w = _db.workouts, we = _db.workoutExercises, s = _db.workoutSets;
    final live = w.deletedAt.isNull() & w.finishedAt.isNotNull() & inRange(w.startedAt);
    final workouts = await (_db.select(w)
          ..where((_) => live)
          ..orderBy([(w) => OrderingTerm(expression: w.startedAt)]))
        .get();
    final rows = await (_db.select(s).join([
      innerJoin(we, we.id.equalsExp(s.workoutExerciseId)),
      innerJoin(w, w.id.equalsExp(we.workoutId)),
    ])
          ..where(live & we.deletedAt.isNull() & we.skipped.not() & s.deletedAt.isNull() & s.isDrop.not() & s.done)
          ..orderBy([OrderingTerm(expression: we.position), OrderingTerm(expression: s.setNumber)]))
        .get();
    final exercises = <String, Map<String, WorkoutExercise>>{}, sets = <String, List<WorkoutSet>>{};
    for (final r in rows) {
      final e = r.readTable(we), x = r.readTable(s);
      if ((x.reps == null) == (x.durationSec == null)) continue; // v1 needs exactly one of them
      (exercises[e.workoutId] ??= {})[e.id] = e;
      (sets[e.id] ??= []).add(x);
    }
    final routines = {for (final r in await _db.select(_db.routines).get()) r.id: r.name};
    final names = <String, String>{}; // exercise row id -> name, looked up once
    final cardio = await (_db.select(_db.cardio)
          ..where((c) => c.deletedAt.isNull() & inRange(c.startedAt))
          ..orderBy([(c) => OrderingTerm(expression: c.startedAt)]))
        .get();
    return jsonEncode({
      'version': 1,
      'workouts': [
        for (final workout in workouts)
          if (exercises[workout.id]?.values.toList() case final es?)
            {
              'date': _localMinute(workout.startedAt),
              'routine': ?routines[workout.routineId],
              'notes': ?workout.notes,
              'exercises': [
                for (final (i, e) in es.indexed)
                  {
                    'name': names[e.exerciseId] ??= (await _catalog.byId(e.exerciseId))?.name ?? 'Unknown exercise',
                    'notes': ?e.notes,
                    // Linked only to the card right after it; a left-out partner would otherwise pass the link on.
                    'supersetWithNext': e.supersetWithNext && i + 1 < es.length && es[i + 1].position == e.position + 1,
                    'sets': [
                      for (final x in sets[e.id]!) {'weightKg': ?x.weightKg, 'reps': ?x.reps, 'durationSec': ?x.durationSec},
                    ],
                  },
              ],
            },
      ],
      'cardio': [
        for (final c in cardio)
          {
            'type': c.type,
            'date': _localMinute(c.startedAt),
            'distanceKm': ?c.distanceKm,
            'durationSec': c.durationSec,
            'avgHr': ?c.avgHr,
            'inclinePct': ?c.inclinePct,
            'rpe': ?c.rpe,
            'notes': ?c.notes,
          },
      ],
    });
  }
}

/// `yyyy-MM-ddTHH:mm` in local time, the v1 date shape.
String _localMinute(DateTime d) => d.toLocal().toIso8601String().substring(0, 16);

String? _blank(Object? s) => s is String && s.trim().isNotEmpty ? s : null;
