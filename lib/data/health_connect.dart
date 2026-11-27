import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cardio.dart';
import 'error_log.dart';
import 'health.dart';
import 'recording.dart';
import 'track.dart';
import 'workouts.dart';

/// Health Connect exercise types (androidx ExerciseSessionRecord.EXERCISE_TYPE_*) that are Runs.
const hcRunning = 56, hcTreadmill = 57;

/// How far back each check reads. Health Connect only serves 30 days before the permission was granted, and re-reading a session changes nothing.
const hcLookback = Duration(days: 30);

/// One exercise session in Health Connect, with the heart-rate samples and totals the same app wrote during it.
class HcSession {
  HcSession({
    required this.id,
    required this.exerciseType,
    required this.start,
    required this.end,
    this.distanceM,
    this.totalKcal,
    this.activeKcal,
    this.hrTimes = const [],
    this.hrBpm = const [],
  });

  /// The map MainActivity.kt (channel `timburr/health`, method `sessions`) returns per session.
  factory HcSession.fromMap(Map m) => HcSession(
        id: m['id'] as String,
        exerciseType: m['type'] as int,
        start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int, isUtc: true),
        end: DateTime.fromMillisecondsSinceEpoch(m['end'] as int, isUtc: true),
        distanceM: (m['distanceM'] as num?)?.toDouble(),
        totalKcal: (m['totalKcal'] as num?)?.toDouble(),
        activeKcal: (m['activeKcal'] as num?)?.toDouble(),
        hrTimes: [for (final t in m['hrTimes'] as List? ?? const []) DateTime.fromMillisecondsSinceEpoch(t as int, isUtc: true)],
        hrBpm: [for (final b in m['hrBpm'] as List? ?? const []) b as int],
      );

  final String id; // Health Connect's record id
  final int exerciseType;
  final DateTime start, end;
  final double? distanceM, totalKcal, activeKcal;
  final List<DateTime> hrTimes; // heart-rate samples, paired with [hrBpm]
  final List<int> hrBpm;

  bool get isRun => exerciseType == hcRunning; // a treadmill session is not a Run: Daniel runs only outside
  int get elapsedSec => end.difference(start).inSeconds;

  /// The session's heart-rate samples inside its time range, in order.
  List<({int sec, int bpm})> get _hr {
    final out = [
      for (var i = 0; i < hrTimes.length && i < hrBpm.length; i++)
        if (!hrTimes[i].isBefore(start) && !hrTimes[i].isAfter(end) && hrBpm[i] > 0) (sec: hrTimes[i].difference(start).inSeconds, bpm: hrBpm[i]),
    ];
    return out..sort((a, b) => a.sec.compareTo(b.sec));
  }

  int? get avgHr {
    final hr = _hr;
    return hr.isEmpty ? null : (hr.fold<int>(0, (a, s) => a + s.bpm) / hr.length).round();
  }

  int? get maxHr {
    final hr = _hr;
    return hr.isEmpty ? null : hr.map((s) => s.bpm).reduce((a, b) => a > b ? a : b);
  }

  /// Calories burned during the session: the total when the app wrote one, else the active calories.
  int? get calories => (totalKcal ?? activeKcal)?.round();
}

/// [s] as a recording for [CardioStore.ingest]; null when it is not a run. It carries the session's heart-rate trace as a track (time and HR
/// only), its distance and calories. Health Connect has no Moving time, so a merge keeps the Run's.
Recording? runRecording(HcSession s) {
  if (!s.isRun || s.elapsedSec <= 0) return null;
  final hr = s._hr;
  final km = s.distanceM == null || s.distanceM! <= 0 ? null : roundTo(s.distanceM! / 1000, 3);
  return Recording(
    source: 'health_connect',
    type: 'run',
    start: s.start,
    elapsedSec: s.elapsedSec,
    externalId: s.id,
    distanceKm: km,
    track: hr.isEmpty ? null : Track(time: [for (final h in hr) h.sec], hr: [for (final h in hr) h.bpm]),
    avgHr: s.avgHr,
    maxHr: s.maxHr,
    calories: s.calories,
  );
}

/// A Workout's Health stats from [s]: average HR, calories and active time (start to end). Health Connect has no effort or cardio load.
HealthStats workoutStats(HcSession s) => (avgHr: s.avgHr, calories: s.calories, activeSec: s.elapsedSec, effort: null, cardioLoad: null);

/// How many Runs and Workouts a check filled in.
typedef HcCheck = ({int runs, int workouts});

/// Hands every run session to [CardioStore.ingest], which merges it into the Run it overlaps and ignores it when there is none. Every other
/// session may fill the empty Health stats of the Workout it overlaps ([WorkoutStore.fillHealth]).
Future<HcCheck> applySessions(CardioStore cardio, WorkoutStore workouts, List<HcSession> sessions) async {
  var runs = 0;
  for (final s in sessions) {
    final r = runRecording(s);
    if (r != null && (await cardio.ingest(r)).outcome == IngestOutcome.merged) runs++;
  }
  final filled = await workouts.fillHealth([
    for (final s in sessions)
      if (!s.isRun && s.elapsedSec > 0) (start: s.start, end: s.end, stats: workoutStats(s)),
  ]);
  return (runs: runs, workouts: filled);
}

/// The app's one Health Connect, set in main (like `liveRecorder`). Null in tests.
HealthConnect? healthConnect;

enum HcStatus { unknown, unavailable, updateNeeded, disconnected, connected }

/// The Fitbit's data through Health Connect. The platform side is MainActivity.kt (channel `timburr/health`); everything it reads goes through
/// [applySessions]. Connected means Daniel granted the exercise permission; disconnecting revokes it.
class HealthConnect {
  HealthConnect(this.cardio, this.workouts);

  final CardioStore cardio;
  final WorkoutStore workouts;
  static const _channel = MethodChannel('timburr/health');

  final status = ValueNotifier(HcStatus.unknown);
  Future<HcCheck>? _running;

  /// Reads the platform state into [status].
  Future<HcStatus> refresh() async {
    try {
      final s = await _channel.invokeMethod<String>('status');
      status.value = switch (s) {
        'available' => await _channel.invokeMethod<bool>('granted') == true ? HcStatus.connected : HcStatus.disconnected,
        'update' => HcStatus.updateNeeded,
        _ => HcStatus.unavailable,
      };
    } on MissingPluginException {
      status.value = HcStatus.unavailable; // not Android
    } catch (e, st) {
      reportError('health_connect', e, st, {'call': 'status'});
      status.value = HcStatus.unavailable;
    }
    return status.value;
  }

  /// Shows the system permission prompt. Call only after the explanation screen.
  Future<HcStatus> connect() async {
    try {
      await _channel.invokeMethod<bool>('request');
    } catch (e, st) {
      reportError('health_connect', e, st, {'call': 'request'});
    }
    return refresh();
  }

  Future<HcStatus> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
    } catch (e, st) {
      reportError('health_connect', e, st, {'call': 'disconnect'});
    }
    return refresh();
  }

  /// Reads the last [hcLookback] of sessions and applies them. Null when not connected. Only one check runs at a time; a second call joins it.
  Future<HcCheck?> check() async {
    if (await refresh() != HcStatus.connected) return null;
    return _running ??= _check().whenComplete(() => _running = null);
  }

  Future<HcCheck> _check() async {
    final now = DateTime.now();
    final raw = await _channel.invokeMethod<List>('sessions', {'from': now.subtract(hcLookback).millisecondsSinceEpoch, 'to': now.millisecondsSinceEpoch});
    return applySessions(cardio, workouts, [for (final m in raw ?? const []) HcSession.fromMap(m as Map)]);
  }

  /// [check] for app start and resume: errors go to the error log, nothing is shown.
  Future<void> checkQuietly() async {
    try {
      await check();
    } catch (e, st) {
      reportError('health_connect', e, st, {'call': 'sessions'});
    }
  }
}
