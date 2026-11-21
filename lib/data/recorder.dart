import 'dart:math';

import 'hr_zones.dart';
import 'recording.dart';
import 'run_analysis.dart';
import 'treadmill.dart';
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

/// A km the runner has just completed: its number, how long it took (Moving time) and its pace.
class KmCue {
  const KmCue(this.km, this.splitSec, this.paceSecPerKm);
  final int km;
  final double splitSec, paceSecPerKm;
}

/// What the voice says at a km boundary.
String kmCueText(KmCue c) {
  final t = c.splitSec.round(), p = c.paceSecPerKm.round();
  final mins = t ~/ 60, secs = t % 60;
  return 'Kilometer ${c.km}. Time ${mins > 0 ? '$mins minute${mins == 1 ? '' : 's'} ' : ''}$secs second${secs == 1 ? '' : 's'}. Pace ${p ~/ 60} ${(p % 60).toString().padLeft(2, '0')} per kilometer.';
}

/// The kinds of [RecorderEvent]. The strings are what the autosave stores, so they must not change.
class EventKind {
  static const start = 'start', position = 'position', tick = 'tick', pause = 'pause', resume = 'resume', lap = 'lap', hr = 'hr';
}

/// An input the recorder was given. The log of these is what gets saved while recording: replaying it rebuilds the recorder exactly.
/// Kinds ([EventKind]): `start` (type, id, pace), `position`, `pause`, `resume`, `lap`, `hr` (bpm), `tick` (treadmill only: time passing, so a killed recording keeps
/// its time). An autosave from an older build may hold `steps` events (the phone's step counter); replay ignores them, and a `start` with `stride` but no `pace`
/// gets the default pace.
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
  Recorder._(this.type, this.start, this.sessionId, this.paceSecPerKm);

  /// A new recording of [type] ('run' or 'treadmill') starting at [at]. [sessionId] becomes the Recording's external id.
  /// A treadmill recording estimates distance as Moving time divided by [paceSecPerKm] (Daniel's usual treadmill pace; the default when null) and ignores GPS.
  factory Recorder.start(String type, DateTime at, String sessionId, {double? paceSecPerKm}) {
    final r = Recorder._(type, at, sessionId, paceSecPerKm ?? defaultTreadmillPaceSecPerKm);
    r._log(RecorderEvent(EventKind.start, at, {'type': type, 'id': sessionId, 'pace': r.paceSecPerKm}));
    return r;
  }

  /// Rebuilds a recorder from its saved [events] (the first is `start`).
  factory Recorder.replay(List<RecorderEvent> events) {
    final first = events.first;
    final r = Recorder._(first.data['type'] as String, first.at, first.data['id'] as String, (first.data['pace'] as num?)?.toDouble() ?? defaultTreadmillPaceSecPerKm);
    for (final e in events) {
      r._log(e);
    }
    return r;
  }

  final String type;
  final DateTime start;
  final String sessionId;
  final double paceSecPerKm; // treadmill: the usual pace the distance estimate uses
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

  final _laps = <int>[];
  final _kmCues = <KmCue>[];
  double _lastKmMoving = 0; // Moving time at the last km mark

  bool get paused => _pausedAt != null;
  bool get isTreadmill => type == 'treadmill';

  /// Lap marks, seconds from the start.
  List<int> get laps => List.unmodifiable(_laps);

  /// The km completed so far, in order. A new one appearing is the moment to speak.
  List<KmCue> get kmCues => List.unmodifiable(_kmCues);

  /// Marks a lap. Ignored while paused.
  void lap(DateTime at) {
    if (!paused) _log(RecorderEvent(EventKind.lap, at));
  }

  /// The last event's time, or [start].
  DateTime get lastEventAt => events.last.at;

  void position(PositionSample s) {
    _lastSeen = s;
    if (isTreadmill || paused) return; // not recorded, not saved
    _log(RecorderEvent(EventKind.position, s.time, {'lat': s.lat, 'lon': s.lon, 'alt': s.altitude, 'acc': s.accuracy}));
  }

  /// A beats-per-minute reading from the band, [at] when it came. Not recorded while paused.
  void heartRate(int bpm, DateTime at) {
    if (paused) return;
    _log(RecorderEvent(EventKind.hr, at, {'bpm': bpm}));
  }

  /// Time passing on a treadmill recording: completes any km (the cue to speak) and, at most every 10 s, is saved as an event so a killed app
  /// keeps its Moving time. Other inputs are not needed for a treadmill to move forward.
  void tick(DateTime at) {
    if (!isTreadmill || paused) return;
    if (at.difference(events.last.at).inSeconds >= 10) {
      _log(RecorderEvent(EventKind.tick, at));
    } else {
      _catchUp(at);
    }
  }

  void pause(DateTime at) {
    if (!paused) _log(RecorderEvent(EventKind.pause, at));
  }

  void resume(DateTime at) {
    if (paused) _log(RecorderEvent(EventKind.resume, at));
  }

  void _log(RecorderEvent e) {
    events.add(e);
    _apply(e);
  }

  void _apply(RecorderEvent e) {
    if (isTreadmill && !paused) _catchUp(e.at);
    switch (e.kind) {
      case EventKind.position:
        _onPosition(PositionSample(
          time: e.at,
          lat: (e.data['lat'] as num).toDouble(),
          lon: (e.data['lon'] as num).toDouble(),
          altitude: (e.data['alt'] as num?)?.toDouble(),
          accuracy: (e.data['acc'] as num?)?.toDouble(),
        ));
      case EventKind.hr:
        _bpm = (e.data['bpm'] as num).round();
        _bpmAt = e.at;
        if (isTreadmill) _treadmillPoint(e.at); // a treadmill has no fixes, so each reading is its own track point
      case EventKind.lap:
        _laps.add(max(0, e.at.difference(start).inMilliseconds / 1000).round());
      case EventKind.pause:
        _closeSlow();
        _pausedAt = e.at;
        _last = null;
      case EventKind.resume:
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
        final before = _dist;
        _dist += step;
        _closeSlow();
        _kmCrossings(before, _dist, last.time, dt);
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

  /// A treadmill track point: time and heart rate only.
  void _treadmillPoint(DateTime at) {
    _t.add(max(0, at.difference(start).inMilliseconds / 1000).round());
    _hrCol.add(_bpm);
  }

  /// Records a cue for each km boundary crossed by the move from distance [before] to [after] (meters), starting at [from] and lasting [dt] s.
  void _kmCrossings(double before, double after, DateTime from, double dt) {
    final step = after - before;
    while (after >= (_kmCues.length + 1) * 1000) {
      final mark = (_kmCues.length + 1) * 1000.0;
      final at = from.difference(start).inMilliseconds / 1000 + dt * (mark - before) / step;
      final moving = at - _pausedSec - _autoSec;
      final split = moving - _lastKmMoving;
      _kmCues.add(KmCue(_kmCues.length + 1, split, split));
      _lastKmMoving = moving;
    }
  }

  /// Treadmill: records a cue for each km the Moving time at [at] has passed. A km takes [paceSecPerKm] by definition.
  void _catchUp(DateTime at) {
    final moving = at.difference(start).inMilliseconds / 1000 - _pausedSec;
    while (moving >= (_kmCues.length + 1) * paceSecPerKm) {
      _kmCues.add(KmCue(_kmCues.length + 1, paceSecPerKm, paceSecPerKm));
    }
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
    final auto = isTreadmill ? 0.0 : _openAutoSec();
    final moving = max(0.0, elapsed - _pausedSec - pausedNow - _autoSec - auto);
    final standing = !paused && auto > 0;
    final bpm = _bpmAt != null && now.difference(_bpmAt!).inSeconds <= hrStaleSec ? _bpm : null;
    final dist = isTreadmill ? moving / paceSecPerKm * 1000 : _dist;
    return RunSnapshot(
      elapsedSec: elapsed.round(),
      movingSec: moving.round(),
      distanceM: dist,
      paused: paused,
      autoPaused: standing,
      gps: gpsSignalOf(_lastSeen, now),
      currentPaceSecPerKm: paused || standing || isTreadmill ? null : _currentPace(),
      avgPaceSecPerKm: dist >= 10 && moving > 0 ? moving / (dist / 1000) : null,
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
    final hrs = _hrCol.nonNulls.toList();
    return Recording(
      source: 'recorded',
      type: type,
      start: start,
      elapsedSec: s.elapsedSec,
      movingSec: s.movingSec,
      externalId: sessionId,
      distanceKm: double.parse((s.distanceM / 1000).toStringAsFixed(3)),
      avgHr: hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
      maxHr: hrs.isEmpty ? null : hrs.reduce(max),
      track: isTreadmill ? _treadmillTrack(s.elapsedSec) : _t.isEmpty ? null : _gpsTrack(),
    );
  }

  Track _gpsTrack() => Track(time: List.of(_t), distance: List.of(_d), lat: List.of(_lat), lon: List.of(_lon), altitude: _alt.any((a) => a != null) ? List.of(_alt) : null, hr: _hrCol.any((h) => h != null) ? List.of(_hrCol) : null, laps: _laps.isEmpty ? null : List.of(_laps));

  /// Time (and heart rate when there was any), with the start and the end as points so laps can be measured. Null when there is nothing to keep.
  Track? _treadmillTrack(int elapsedSec) {
    final hasHr = _hrCol.any((h) => h != null);
    if (!hasHr && _laps.isEmpty) return null;
    final laps = _laps.isEmpty ? null : List.of(_laps);
    if (laps == null) return Track(time: List.of(_t), hr: List.of(_hrCol));
    return Track(time: [0, ..._t, elapsedSec], hr: hasHr ? [null, ..._hrCol, null] : null, laps: laps); // start and end points, so laps can be measured
  }
}
