import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'best_efforts.dart';
import 'db.dart';
import 'recording.dart';
import 'settings.dart';
import 'stride.dart';
import 'track.dart';

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

/// "m:ss" under an hour, else "h:mm:ss".
String formatDuration(int s) {
  String two(int n) => n.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}' : '${s ~/ 60}:${two(s % 60)}';
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

enum IngestOutcome { created, merged, unchanged, ignored }

/// What [CardioStore.ingest] did. [id] is the Run written or matched; null for a dry run that would create one, and for [IngestOutcome.ignored]:
/// a Health Connect session that overlaps no Run, which never creates one.
class IngestResult {
  IngestResult(this.id, this.outcome);
  final String? id;
  final IngestOutcome outcome;
}

/// Which source wins a field when the phone's recording and an import disagree, by the Run's type. Nothing else is ever replaced: an import into an
/// imported Run only fills what is empty.
/// Outdoor Run: route, distance and pace from the phone's GPS (`recorded`), heart rate from the Fitbit (`health_connect`).
/// Treadmill run: time from the phone, heart rate and distance from the Fitbit (until Daniel corrects it, which is an edit and always wins).
String? _preferredSource(String type, String column) => switch (column) {
      'type' || 'duration_sec' => 'recorded',
      'distance_km' => type == 'treadmill' ? 'health_connect' : 'recorded',
      'elevation_gain_m' => type == 'treadmill' ? null : 'recorded',
      'avg_hr' || 'max_hr' || 'calories' || 'avg_cadence' => 'health_connect',
      _ => null,
    };

DateTime _wholeSeconds(DateTime d) => DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch ~/ 1000 * 1000, isUtc: d.isUtc); // the column stores seconds
DateTime _endOf(CardioData c) => c.startedAt.add(Duration(seconds: c.elapsedSec ?? c.durationSec));

/// Cardio sessions. Every write goes through [AppDb.save].
class CardioStore {
  CardioStore(this._db, {this.onSaved});
  final AppDb _db;

  /// The settings row, for the Run page's zones and More. Shares this store's sync hook.
  late final settings = SettingsStore(_db, onSaved: onSaved);

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
    await _db.rebuildBestEfforts([id]); // the type may have changed
    unawaited(onSaved?.call()); // sync in the background; the local write is done
    return id;
  }

  /// The one way a recording reaches the store, whatever its source. The same source and external id again changes nothing; a recording whose
  /// times overlap a Run merges into it; anything else becomes a new Run, except a Health Connect session: the Fitbit only fills in Runs Daniel recorded
  /// or imported, so one that overlaps nothing is ignored. A dry run reports the outcome without writing.
  ///
  /// Merging, per field: a field in `edited_fields` is never touched, nor is any value on a hand-typed Run. Otherwise the field's preferred source
  /// ([_preferredSource]) replaces a value between the phone's recording and an import; everything else only fills an empty field. The span runs from the earliest
  /// start to the latest end. The track is merged column by column ([fillMissingColumns]): the live recording's track is the base and a column it lacks is filled from the other.
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
      if (match == null && r.source == 'health_connect') return IngestResult(null, IngestOutcome.ignored);
      if (match == null) {
        final id = const Uuid().v4();
        if (dryRun) return IngestResult(null, IngestOutcome.created);
        await _db.save(_db.cardio, {
          'id': id,
          'type': r.type,
          'started_at': start,
          'distance_km': r.distanceKm,
          'duration_sec': r.moving,
          'elapsed_sec': r.elapsedSec,
          'source': r.source,
          'external_id': r.externalId,
          'avg_hr': r.avgHr,
          'max_hr': r.maxHr,
          'calories': r.calories,
          'avg_cadence': r.avgCadence,
          'elevation_gain_m': r.elevation,
          'notes': r.notes,
          'route': r.route,
        });
        if (r.track != null) await _saveTrack(id, r.track!);
        return IngestResult(id, IngestOutcome.created);
      }

      final edited = match.editedFields.toSet();
      final handTyped = match.source == null || match.source == 'manual';
      final changes = <String, Object?>{};
      var type = match.type; // the Run's type once this recording is merged: it decides who is preferred for the other fields
      void put(String column, Object? incoming, Object? current) {
        if (incoming == null || incoming == current || edited.contains(column)) return;
        final replaces = !handTyped && r.source != match.source && _preferredSource(type, column) == r.source && (r.source == 'recorded' || match.source == 'recorded'); // import against import: fill only
        if (current == null || replaces) changes[column] = incoming;
      }

      put('type', r.type, match.type);
      type = (changes['type'] as String?) ?? type;
      put('distance_km', r.distanceKm, match.distanceKm);
      put('duration_sec', r.moving, match.durationSec);
      put('avg_hr', r.avgHr, match.avgHr);
      put('max_hr', r.maxHr, match.maxHr);
      put('calories', r.calories, match.calories);
      put('avg_cadence', r.avgCadence, match.avgCadence);
      put('elevation_gain_m', r.elevation, match.elevationGainM);
      put('notes', r.notes, match.notes); // Daniel's words: nobody prefers an import's
      final takesOver = r.source == 'recorded' && !handTyped && match.source != 'recorded' && r.externalId != null;
      if (takesOver) { // the live recording becomes the Run's identity
        changes['source'] = r.source;
        changes['external_id'] = r.externalId;
      }

      final newStart = edited.contains('started_at') || !start.isBefore(match.startedAt) ? match.startedAt : start;
      final newEnd = _endOf(match).isAfter(end) ? _endOf(match) : end;
      final elapsed = edited.contains('elapsed_sec') ? match.elapsedSec : newEnd.difference(newStart).inSeconds;
      if (!newStart.isAtSameMomentAs(match.startedAt)) changes['started_at'] = newStart;
      if (elapsed != match.elapsedSec) changes['elapsed_sec'] = elapsed;

      final stored = await _storedTrack(match.id);
      final storedOffset = match.startedAt.difference(newStart).inSeconds;
      Track? track; // the merged track, null when there is none to write
      if (r.track != null) {
        final incomingOffset = start.difference(newStart).inSeconds;
        track = stored == null
            ? shiftedBy(r.track!, incomingOffset)
            : takesOver
                ? fillMissingColumns(r.track!, incomingOffset, stored, storedOffset) ?? shiftedBy(r.track!, incomingOffset)
                : fillMissingColumns(stored, storedOffset, r.track!, incomingOffset) ?? shiftedBy(stored, storedOffset);
      } else if (stored != null) {
        track = shiftedBy(stored, storedOffset);
      }
      if (track != null && stored != null && track.encode() == stored.encode()) track = null;
      if (track != null && !edited.contains('route')) {
        final route = drawsRoute(changes['type'] as String? ?? match.type) ? simplifyRoute(track) : null;
        if (route != match.route) changes['route'] = route;
      }

      if (changes.isEmpty && track == null) return IngestResult(match.id, IngestOutcome.unchanged);
      if (!dryRun) {
        if (changes.isNotEmpty) await _db.save(_db.cardio, {..._columns(match), ...changes});
        if (track != null) await _saveTrack(match.id, track);
      }
      return IngestResult(match.id, IngestOutcome.merged);
    });
    if (!dryRun && (result.outcome == IngestOutcome.created || result.outcome == IngestOutcome.merged)) {
      await _db.rebuildBestEfforts([result.id!]);
      unawaited(onSaved?.call()); // sync in the background; the local write is done
    }
    return result;
  }

  Future<Track?> _storedTrack(String cardioId) async {
    final row = await _db.liveTrackRow(cardioId).getSingleOrNull();
    return row == null ? null : Track.decode(row.points);
  }

  Future<void> _saveTrack(String cardioId, Track t) =>
      _db.save(_db.cardioTracks, {'id': trackRowId(cardioId), 'cardio_id': cardioId, 'points': t.encode(), 'deleted_at': null});

  /// Sets columns of a Run (SQL names to values) as Daniel's own edits: later recordings and syncs never replace them.
  Future<void> edit(String id, Map<String, Object?> fields) async {
    final c = await watch(id).first;
    await _db.save(_db.cardio, {..._columns(c), ...fields, 'edited_fields': {...c.editedFields, ...fields.keys}.toList()});
    await _db.rebuildBestEfforts([id]);
    unawaited(onSaved?.call()); // sync in the background; the local write is done
  }

  /// The Check distance step of a treadmill Run: saves the treadmill's [km] as Daniel's own edit and calibrates the stride from it ([steps] counted).
  Future<void> checkDistance(String id, {required double km, required int steps}) async {
    await edit(id, {'distance_km': km});
    final current = await settings.watch().first;
    final before = current?.strideSamples ?? 0;
    final next = calibrateStride(current?.strideM, before, steps, km);
    if (next.samples != before) await settings.setStride(next.strideM, next.samples);
  }

  /// Cached Best efforts of live outdoor Runs, every distance.
  Stream<List<Effort>> watchBestEfforts() => _db.watchBestEfforts();

  /// The Run's points, null when it has none.
  Stream<Track?> watchTrack(String cardioId) => _db.liveTrackRow(cardioId)
      .watchSingleOrNull()
      .map((t) => t == null ? null : Track.decode(t.points));

  /// The tracks of live Runs that have heart rate, by Run id. For Relative Effort over all Runs.
  Stream<Map<String, Track>> watchHrTracks() => (_db.select(_db.cardioTracks)..where((t) => t.deletedAt.isNull())).watch().map((rows) {
        final out = <String, Track>{};
        for (final r in rows) {
          final t = Track.decode(r.points);
          if (t.hr != null) out[r.cardioId] = t;
        }
        return out;
      });

  /// Every column of [c] by SQL name; [AppDb.save] needs the required ones even to update.
  Map<String, Object?> _columns(CardioData c) => c.toColumns(false).map((k, v) => MapEntry(k, (v as Variable).value));

  /// Soft-deletes the Run and its track.
  Future<void> delete(String id) async {
    final c = await watch(id).first;
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.save(_db.cardio, {..._columns(c), 'deleted_at': now});
      final track = await _db.liveTrackRow(id).getSingleOrNull();
      if (track != null) await _db.save(_db.cardioTracks, {'id': track.id, 'cardio_id': id, 'points': track.points, 'deleted_at': now});
      await _db.rebuildBestEfforts([id]);
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
