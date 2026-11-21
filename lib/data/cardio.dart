import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'recording.dart';
import 'records.dart' show Series;
import 'track.dart';
import 'stats.dart' show mondayOf;

/// The types Timburr records. Old backups and the database may still hold others (walk, bike, swim, sports); they load but are not offered.
const cardioTypes = ['run', 'treadmill'];

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

/// Server column caps (supabase/migrations): Postgres int, numeric(7, 3) distance, numeric(4, 1) incline.
const int4Max = 2147483647;
const distanceBelow = 10000;
const inclineBelow = 1000;

/// [v] rounded to [places] decimals, as a numeric(p, places) column stores it.
double roundTo(num v, int places) => double.parse(v.toStringAsFixed(places));

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
  if ((km == null || roundTo(km, 3) <= 0 || roundTo(km, 3) >= distanceBelow)) {
    e['distance'] = 'Enter a distance above 0 and below $distanceBelow';
  }
  final sec = parseDuration(duration);
  if (sec == null || sec <= 0 || sec > int4Max) e['duration'] = 'Enter a duration like 27:30';
  final hr = int.tryParse(avgHr.trim());
  if (avgHr.trim().isNotEmpty && (hr == null || hr <= 0 || hr > int4Max)) e['avgHr'] = 'Enter a whole number above 0';
  final inc = parseNum(incline);
  if (incline.trim().isNotEmpty && (inc == null || inc < 0 || roundTo(inc, 1) >= inclineBelow)) {
    e['incline'] = 'Enter 0 to 999.9';
  }
  if (rpe.trim().isNotEmpty) {
    final r = int.tryParse(rpe.trim());
    if (r == null || r < 1 || r > 10) e['rpe'] = 'Enter 1 to 10';
  }
  return e;
}

enum IngestOutcome { created, merged, unchanged }

/// What [CardioStore.ingest] did. [id] is the Run written or matched; null for a dry run that would create one.
class IngestResult {
  IngestResult(this.id, this.outcome);
  final String? id;
  final IngestOutcome outcome;
}

/// Who wins a field when two recordings disagree: Daniel's own entries, then the phone's live recording, then imports (file, Health Connect).
/// Imports have the same rank, so they never replace each other; they only fill what is empty.
int _rank(String? source) => switch (source) { null || 'manual' => 3, 'recorded' => 2, _ => 1 };

DateTime _wholeSeconds(DateTime d) => DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch ~/ 1000 * 1000, isUtc: d.isUtc); // the column stores seconds
DateTime _endOf(CardioData c) => c.startedAt.add(Duration(seconds: c.elapsedSec ?? c.durationSec));

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

  /// The one way a recording reaches the store, whatever its source. The same source and external id again changes nothing; a recording whose
  /// times overlap a Run merges into it; anything else becomes a new Run. A dry run reports the outcome without writing.
  ///
  /// Merging, per field: [_rank] decides, an equal or lower rank only fills an empty field, and fields in `edited_fields` are never touched.
  /// The span runs from the earliest start to the latest end. A track replaces the Run's only when the recording outranks the Run's source, else it fills a missing one.
  Future<IngestResult> ingest(Recording r, {bool dryRun = false}) async {
    final result = await _db.transaction(() async {
      final start = _wholeSeconds(r.start), end = start.add(Duration(seconds: r.elapsedSec));
      if (r.externalId != null) {
        final same = await (_db.select(_db.cardio)..where((c) => c.source.equals(r.source) & c.externalId.equals(r.externalId!))).get(); // deleted Runs count: a deleted Run stays deleted
        if (same.isNotEmpty) return IngestResult(same.first.id, IngestOutcome.unchanged);
      }
      final candidates = await (_db.select(_db.cardio)
            ..where((c) => c.deletedAt.isNull() & c.type.isIn(cardioTypes) & c.startedAt.isSmallerThanValue(end) & c.startedAt.isBiggerThanValue(start.subtract(const Duration(days: 2))))
            ..orderBy([(c) => OrderingTerm.asc(c.startedAt)]))
          .get();
      final match = candidates.where((c) => _endOf(c).isAfter(start)).firstOrNull;
      if (match == null) {
        final id = const Uuid().v4();
        if (dryRun) return IngestResult(null, IngestOutcome.created);
        await _db.save(_db.cardio, {
          'id': id,
          'type': r.type,
          'started_at': start,
          'distance_km': r.distanceKm,
          'duration_sec': r.movingSec,
          'elapsed_sec': r.elapsedSec,
          'source': r.source,
          'external_id': r.externalId,
          'avg_hr': r.avgHr,
          'max_hr': r.maxHr,
          'calories': r.calories,
          'avg_cadence': r.avgCadence,
          'elevation_gain_m': r.elevationGainM,
          'notes': r.notes,
          'route': r.route,
        });
        if (r.track != null) await _saveTrack(id, r.track!);
        return IngestResult(id, IngestOutcome.created);
      }

      final edited = match.editedFields.toSet();
      final wins = _rank(r.source) > _rank(match.source);
      final changes = <String, Object?>{};
      void put(String column, Object? incoming, Object? current, {bool overwrite = true}) {
        if (incoming == null || incoming == current || edited.contains(column)) return;
        if (current == null || (overwrite && wins)) changes[column] = incoming;
      }

      put('type', r.type, match.type);
      put('distance_km', r.distanceKm, match.distanceKm);
      put('duration_sec', r.movingSec, match.durationSec);
      put('avg_hr', r.avgHr, match.avgHr);
      put('max_hr', r.maxHr, match.maxHr);
      put('calories', r.calories, match.calories);
      put('avg_cadence', r.avgCadence, match.avgCadence);
      put('elevation_gain_m', r.elevationGainM, match.elevationGainM);
      put('notes', r.notes, match.notes, overwrite: false); // Daniel's words, an import only fills them in
      final writeTrack = r.track != null && (wins || await _hasTrack(match.id) == false);
      if (writeTrack) put('route', r.route, match.route);
      if (wins) {
        changes['source'] = r.source;
        changes['external_id'] = r.externalId;
      }

      final newStart = edited.contains('started_at') || !start.isBefore(match.startedAt) ? match.startedAt : start;
      final newEnd = _endOf(match).isAfter(end) ? _endOf(match) : end;
      final elapsed = edited.contains('elapsed_sec') ? match.elapsedSec : newEnd.difference(newStart).inSeconds;
      if (!newStart.isAtSameMomentAs(match.startedAt)) changes['started_at'] = newStart;
      if (elapsed != match.elapsedSec) changes['elapsed_sec'] = elapsed;

      if (changes.isEmpty && !writeTrack) return IngestResult(match.id, IngestOutcome.unchanged);
      if (!dryRun) {
        if (changes.isNotEmpty) await _db.save(_db.cardio, {..._columns(match), ...changes});
        if (writeTrack) await _saveTrack(match.id, r.track!);
      }
      return IngestResult(match.id, IngestOutcome.merged);
    });
    if (!dryRun && result.outcome != IngestOutcome.unchanged) unawaited(onSaved?.call()); // sync in the background; the local write is done
    return result;
  }

  Future<bool> _hasTrack(String cardioId) async => (await (_db.select(_db.cardioTracks)..where((t) => t.cardioId.equals(cardioId) & t.deletedAt.isNull())).get()).isNotEmpty;

  Future<void> _saveTrack(String cardioId, Track t) =>
      _db.save(_db.cardioTracks, {'id': trackRowId(cardioId), 'cardio_id': cardioId, 'points': t.encode(), 'deleted_at': null});

  /// Sets columns of a Run (SQL names to values) as Daniel's own edits: later recordings and syncs never replace them.
  Future<void> edit(String id, Map<String, Object?> fields) async {
    final c = await watch(id).first;
    await _db.save(_db.cardio, {..._columns(c), ...fields, 'edited_fields': {...c.editedFields, ...fields.keys}.toList()});
    unawaited(onSaved?.call()); // sync in the background; the local write is done
  }

  /// The Run's points, null when it has none.
  Stream<Track?> watchTrack(String cardioId) => (_db.select(_db.cardioTracks)..where((t) => t.cardioId.equals(cardioId) & t.deletedAt.isNull()))
      .watchSingleOrNull()
      .map((t) => t == null ? null : Track.decode(t.points));

  /// Every column of [c] by SQL name; [AppDb.save] needs the required ones even to update.
  Map<String, Object?> _columns(CardioData c) => c.toColumns(false).map((k, v) => MapEntry(k, (v as Variable).value));

  Future<void> delete(String id) async {
    final c = await watch(id).first;
    await _db.save(_db.cardio, {..._columns(c), 'deleted_at': DateTime.now()});
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
    final monday = mondayOf(s.startedAt);
    final (sec, n) = weeks[monday] ?? (0, 0);
    weeks[monday] = (sec + s.durationSec, n + 1);
  }
  return [for (final k in weeks.keys.toList()..sort()) (k, weeks[k]!.$1, weeks[k]!.$2)];
}
