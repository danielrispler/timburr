import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'records.dart' show Series;

const distanceTypes = ['run', 'walk', 'treadmill', 'bike', 'swim'];
const sportTypes = ['padel', 'tennis', 'soccer', 'basketball'];
const cardioTypes = [...distanceTypes, ...sportTypes];

/// Sports log time only; the rest log a distance too.
bool hasDistance(Object? type) => !sportTypes.contains(type);

/// Seconds per km, or null when there is no distance.
double? paceSecPerKm(double? distanceKm, int durationSec) =>
    distanceKm != null && distanceKm > 0 ? durationSec / distanceKm : null;

/// Pace as m:ss per km.
String formatPace(double secPerKm) {
  final s = secPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "m:ss", "h:mm:ss" or bare minutes to seconds; null when unreadable.
int? parseDuration(String text) {
  final parts = text.trim().split(':');
  if (parts.length > 3) return null;
  final nums = [for (final p in parts) int.tryParse(p)];
  if (nums.any((n) => n == null || n < 0)) return null;
  if (parts.length == 1) return nums[0]! * 60;
  if (nums.skip(1).any((n) => n! > 59)) return null;
  return nums.fold<int>(0, (acc, n) => acc * 60 + n!);
}

/// Parses a number, accepting a decimal comma.
double? parseNum(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// Field name to error message; empty when the form can be saved. Optional fields may be blank.
Map<String, String> validateCardio({
  required String? type,
  required String distance,
  required String duration,
  String avgHr = '',
  String incline = '',
  String rpe = '',
}) {
  final e = <String, String>{};
  if (!cardioTypes.contains(type)) e['type'] = 'Pick a type';
  final km = parseNum(distance);
  if (hasDistance(type) && (km == null || km <= 0)) e['distance'] = 'Enter a distance above 0';
  final sec = parseDuration(duration);
  if (sec == null || sec <= 0) e['duration'] = 'Enter a duration like 27:30';
  if (avgHr.trim().isNotEmpty && ((int.tryParse(avgHr.trim()) ?? 0) <= 0)) e['avgHr'] = 'Enter a whole number above 0';
  if (incline.trim().isNotEmpty && ((parseNum(incline) ?? -1) < 0)) e['incline'] = 'Enter 0 or more';
  if (rpe.trim().isNotEmpty) {
    final r = int.tryParse(rpe.trim());
    if (r == null || r < 1 || r > 10) e['rpe'] = 'Enter 1 to 10';
  }
  return e;
}

/// Cardio sessions. Every write goes through [AppDb.save].
class CardioStore {
  CardioStore(this._db, {this.onSaved});
  final AppDb _db;

  /// Called after each save or delete; main wires it to sync.
  final Future<void> Function()? onSaved;

  /// Creates a session, or replaces every field of [id]. Returns its id.
  Future<String> save({
    String? id,
    required String type,
    required DateTime startedAt,
    required double? distanceKm,
    required int durationSec,
    int? avgHr,
    double? inclinePct,
    int? rpe,
    String? notes,
  }) async {
    id ??= const Uuid().v4();
    await _db.save(_db.cardio, {
      'id': id,
      'type': type,
      'started_at': startedAt,
      'distance_km': distanceKm,
      'duration_sec': durationSec,
      'avg_hr': avgHr,
      'incline_pct': inclinePct,
      'rpe': rpe,
      'notes': notes,
    });
    unawaited(onSaved?.call()); // sync in the background; the local write is done
    return id;
  }

  Future<void> delete(String id) async {
    final c = await watch(id).first;
    await _db.save(_db.cardio, {
      ...c.toColumns(false).map((k, v) => MapEntry(k, (v as Variable).value)),
      'deleted_at': DateTime.now(),
    });
    unawaited(onSaved?.call()); // sync in the background; the local write is done
  }

  Stream<CardioData> watch(String id) => (_db.select(_db.cardio)..where((c) => c.id.equals(id))).watchSingle();

  /// Non-deleted sessions, newest first.
  Stream<List<CardioData>> watchAll() => (_db.select(_db.cardio)
        ..where((c) => c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.desc(c.startedAt)]))
      .watch();
}

/// Workouts and cardio in one list, newest first; [strength] / [cardio] false drop that kind.
List<Object> mergeHistory(List<Workout> workouts, List<CardioData> sessions, {bool strength = true, bool cardio = true}) {
  DateTime at(Object o) => o is Workout ? o.startedAt : (o as CardioData).startedAt;
  return [if (strength) ...workouts, if (cardio) ...sessions]..sort((a, b) => at(b).compareTo(at(a)));
}

const distanceBuckets = [5, 10];

/// 5 or 10 when [km] is within 5% of it (GPS and treadmill drift), else null.
int? distanceBucket(double? km) {
  if (km == null) return null;
  for (final b in distanceBuckets) {
    if ((km - b).abs() <= b * 0.05 + 1e-9) return b;
  }
  return null;
}

/// [sessions] narrowed to [type] and [bucket] when given; order kept.
List<CardioData> filterCardio(List<CardioData> sessions, {String? type, int? bucket}) => [
      for (final s in sessions)
        if ((type == null || s.type == type) && (bucket == null || distanceBucket(s.distanceKm) == bucket)) s,
    ];

/// Shortest duration in [bucket], or null. Filter by type first: a bike 10 km is not a run 10 km.
CardioData? bestTime(List<CardioData> sessions, int bucket) {
  CardioData? best;
  for (final s in filterCardio(sessions, bucket: bucket)) {
    if (best == null || s.durationSec < best.durationSec) best = s;
  }
  return best;
}

/// (date, sec/km) oldest first, for the pace chart.
Series paceSeries(List<CardioData> sessions) => [
      for (final s in [...sessions]..sort((a, b) => a.startedAt.compareTo(b.startedAt)))
        if (paceSecPerKm(s.distanceKm, s.durationSec) case final p?) (s.startedAt, p),
    ];

/// (Monday of the week, total seconds, session count), oldest first, for sports stats.
List<(DateTime, int, int)> weeklyTotals(List<CardioData> sessions) {
  final weeks = <DateTime, (int, int)>{};
  for (final s in sessions) {
    final d = s.startedAt;
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    final (sec, n) = weeks[monday] ?? (0, 0);
    weeks[monday] = (sec + s.durationSec, n + 1);
  }
  return [for (final k in weeks.keys.toList()..sort()) (k, weeks[k]!.$1, weeks[k]!.$2)];
}
