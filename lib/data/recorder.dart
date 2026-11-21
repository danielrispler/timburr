import 'dart:math';

import 'hr_zones.dart';
import 'recording.dart';
import 'run_analysis.dart';
import 'track.dart';

/// One fix from the phone's location sensor.
class PositionSample {
  const PositionSample({required this.time, required this.lat, required this.lon, this.altitude, this.accuracy});

  final DateTime time;
  final double lat, lon;
  final double? altitude;
  final double? accuracy; // meters, 68% radius
}

enum GpsSignal { none, weak, good }

/// Fixes vaguer than this (meters) are not used for the route.
const maxAccuracyM = 30.0;

/// Good at 20 m or better, weak above, none when the last fix is older than 10 s or there is none.
GpsSignal gpsSignalOf(PositionSample? last, DateTime now) {
  if (last == null || now.difference(last.time).inSeconds > 10) return GpsSignal.none;
  return last.accuracy != null && last.accuracy! <= 20 ? GpsSignal.good : GpsSignal.weak;
}

/// An input the recorder was given. The log of these is what gets saved while recording: replaying it rebuilds the recorder exactly.
/// Kinds: `start` (type, id), `position`, `pause`, `resume`, `hr` (bpm).
/// shortcut for later tickets: heart rate (#68), laps (#69) and treadmill steps (#70) are new kinds with their own `data`; add a case in [Recorder] `_apply`.
class RecorderEvent {
  const RecorderEvent(this.kind, this.at, [this.data = const {}]);

  final String kind;
  final DateTime at;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {'k': kind, 'at': at.toUtc().toIso8601String(), 'd': data};

  factory RecorderEvent.fromJson(Map<String, Object?> j) =>
      RecorderEvent(j['k'] as String, DateTime.parse(j['at'] as String), Map<String, Object?>.from(j['d'] as Map? ?? const {}));
}

/// What the recording screen shows.
class RunSnapshot {
  const RunSnapshot({
    required this.elapsedSec,
    required this.movingSec,
    required this.distanceM,
    required this.paused,
    required this.autoPaused,
    required this.gps,
    this.currentPaceSecPerKm,
    this.avgPaceSecPerKm,
    this.hr,
    this.hrZone,
  });

  final int elapsedSec; // clock time since the start, pauses included
  final int movingSec; // Moving time
  final double distanceM;
  final bool paused; // Daniel paused it
  final bool autoPaused; // standing still
  final GpsSignal gps;
  final double? currentPaceSecPerKm, avgPaceSecPerKm;
  final int? hr, hrZone; // live beats per minute and its zone (1-5); null when the band is silent
}

/// A heart-rate reading stands for this long; after it the point or the display has a gap.
const hrStaleSec = 10;

/// The live recording as a pure state machine: fixes and button presses in, a [Recording] out. It never reads a clock; every input carries its time,
/// so tests drive it with fake streams. The platform (GPS, foreground service, autosave) lives in `LiveRecorder`.
class Recorder {
  Recorder._(this.type, this.start, this.sessionId);

  /// A new recording of [type] ('run' or 'treadmill') starting at [at]. [sessionId] becomes the Recording's external id.
  factory Recorder.start(String type, DateTime at, String sessionId) {
    final r = Recorder._(type, at, sessionId);
    r._log(RecorderEvent('start', at, {'type': type, 'id': sessionId}));
    return r;
  }

  /// Rebuilds a recorder from its saved [events] (the first is `start`).
  factory Recorder.replay(List<RecorderEvent> events) {
    final first = events.first;
    final r = Recorder._(first.data['type'] as String, first.at, first.data['id'] as String);
    for (final e in events) {
      r._log(e);
    }
    return r;
  }

  final String type;
  final DateTime start;
  final String sessionId;
  final List<RecorderEvent> events = [];

  // Track columns of the accepted fixes.
  final _t = <int?>[], _d = <double?>[], _lat = <double?>[], _lon = <double?>[], _alt = <double?>[], _hrCol = <int?>[];
  int? _bpm; // latest heart-rate reading and when it came
  DateTime? _bpmAt;
  PositionSample? _last; // last accepted fix of the current stretch
  PositionSample? _lastSeen; // any fix, for the GPS indicator
  double _dist = 0;
  DateTime? _pausedAt;
  double _pausedSec = 0, _autoSec = 0;
  DateTime? _slowSince; // when the current slow stretch began

  bool get paused => _pausedAt != null;

  /// The last event's time, or [start].
  DateTime get lastEventAt => events.last.at;

  void position(PositionSample s) {
    _lastSeen = s;
    if (paused) return; // not recorded, not saved
    _log(RecorderEvent('position', s.time, {'lat': s.lat, 'lon': s.lon, 'alt': s.altitude, 'acc': s.accuracy}));
  }

  /// A beats-per-minute reading from the band, [at] when it came. Not recorded while paused.
  void heartRate(int bpm, DateTime at) {
    if (paused) return;
    _log(RecorderEvent('hr', at, {'bpm': bpm}));
  }

  void pause(DateTime at) {
    if (!paused) _log(RecorderEvent('pause', at));
  }

  void resume(DateTime at) {
    if (paused) _log(RecorderEvent('resume', at));
  }

  void _log(RecorderEvent e) {
    events.add(e);
    _apply(e);
  }

  void _apply(RecorderEvent e) {
    switch (e.kind) {
      case 'position':
        _onPosition(PositionSample(
          time: e.at,
          lat: (e.data['lat'] as num).toDouble(),
          lon: (e.data['lon'] as num).toDouble(),
          altitude: (e.data['alt'] as num?)?.toDouble(),
          accuracy: (e.data['acc'] as num?)?.toDouble(),
        ));
      case 'hr':
        _bpm = (e.data['bpm'] as num).round();
        _bpmAt = e.at;
      case 'pause':
        _closeSlow();
        _pausedAt = e.at;
        _last = null;
      case 'resume':
        _pausedSec += e.at.difference(_pausedAt!).inMilliseconds / 1000;
        _pausedAt = null;
        _last = null; // the next fix starts a new stretch: whatever happened during the pause is not distance
    }
  }

  void _onPosition(PositionSample s) {
    _lastSeen = s;
    if (s.accuracy != null && s.accuracy! > maxAccuracyM) return;
    final last = _last;
    if (last != null) {
      final dt = s.time.difference(last.time).inMilliseconds / 1000;
      if (dt <= 0) return;
      final step = haversineM(last.lat, last.lon, s.lat, s.lon);
      if (step > maxRunSpeed * max(1, dt)) return; // a GPS jump
      if (step / dt >= autoPauseSpeed) {
        _dist += step;
        _closeSlow();
      } else {
        _slowSince ??= last.time;
      }
    }
    _last = s;
    _t.add(max(0, s.time.difference(start).inMilliseconds / 1000).round());
    _d.add(_dist);
    _lat.add(s.lat);
    _lon.add(s.lon);
    _alt.add(s.altitude);
    _hrCol.add(_bpmAt != null && s.time.difference(_bpmAt!).inSeconds <= hrStaleSec ? _bpm : null);
  }

  /// Ends the slow stretch: counted as auto-paused when it lasted [autoPauseSec] or more (as `autoPauseMovingSec` does for a finished track).
  void _closeSlow() {
    _autoSec += _openAutoSec();
    _slowSince = null;
  }

  double _openAutoSec() {
    final since = _slowSince, last = _last;
    if (since == null || last == null) return 0;
    final len = last.time.difference(since).inMilliseconds / 1000;
    return len >= autoPauseSec ? len : 0;
  }

  /// The numbers at [now]. [maxHr] picks the zone of the live heart rate.
  RunSnapshot snapshot(DateTime now, {int maxHr = defaultMaxHr}) {
    final elapsed = max(0.0, now.difference(start).inMilliseconds / 1000);
    final pausedNow = _pausedAt == null ? 0.0 : now.difference(_pausedAt!).inMilliseconds / 1000;
    final auto = _openAutoSec();
    final moving = max(0.0, elapsed - _pausedSec - pausedNow - _autoSec - auto);
    final standing = !paused && auto > 0;
    final bpm = _bpmAt != null && now.difference(_bpmAt!).inSeconds <= hrStaleSec ? _bpm : null;
    return RunSnapshot(
      elapsedSec: elapsed.round(),
      movingSec: moving.round(),
      distanceM: _dist,
      paused: paused,
      autoPaused: standing,
      gps: gpsSignalOf(_lastSeen, now),
      currentPaceSecPerKm: paused || standing ? null : _currentPace(),
      avgPaceSecPerKm: _dist >= 10 && moving > 0 ? moving / (_dist / 1000) : null,
      hr: bpm,
      hrZone: bpm == null ? null : zoneOf(bpm, maxHr),
    );
  }

  /// Pace over roughly the last 10 s.
  double? _currentPace() {
    if (_t.length < 2) return null;
    final end = _t.length - 1;
    var from = end - 1;
    while (from > 0 && _t[end]! - _t[from]! < 10) {
      from--;
    }
    final dt = _t[end]! - _t[from]!, dm = _d[end]! - _d[from]!;
    return dt <= 0 || dm / dt < autoPauseSpeed ? null : 1000 / (dm / dt);
  }

  /// The finished recording, ending at [end]. It goes to `CardioStore.ingest`.
  Recording finish(DateTime end) {
    final s = snapshot(end);
    return Recording(
      source: 'recorded',
      type: type,
      start: start,
      elapsedSec: s.elapsedSec,
      movingSec: s.movingSec,
      externalId: sessionId,
      distanceKm: double.parse((s.distanceM / 1000).toStringAsFixed(3)),
      track: _t.isEmpty
          ? null
          : Track(time: List.of(_t), distance: List.of(_d), lat: List.of(_lat), lon: List.of(_lon), altitude: _alt.any((a) => a != null) ? List.of(_alt) : null, hr: _hrCol.any((h) => h != null) ? List.of(_hrCol) : null),
    );
  }
}
