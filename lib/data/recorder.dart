import 'dart:math';

import 'hr_zones.dart';
import 'intervals.dart';
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

/// A km the runner has just completed: its number, how long it took (Moving time) and its pace.
class KmCue {
  const KmCue(this.km, this.splitSec, this.paceSecPerKm);
  final int km;
  final double splitSec, paceSecPerKm;
}

/// What the voice says at a km boundary.
String kmCueText(KmCue c) {
  final t = c.splitSec.round();
  final mins = t ~/ 60, secs = t % 60;
  return 'Kilometer ${c.km}. Time ${mins > 0 ? '$mins minute${mins == 1 ? '' : 's'} ' : ''}$secs second${secs == 1 ? '' : 's'}. ${_spokenPace(c.paceSecPerKm)}.';
}

String _spokenPace(double secPerKm) => 'Pace ${_paceWords(secPerKm)}';

/// "4 05 per kilometer".
String _paceWords(num secPerKm) {
  final p = secPerKm.round();
  return '${p ~/ 60} ${(p % 60).toString().padLeft(2, '0')} per kilometer';
}

/// A rep's pace against its Target pace: "On target.", "5 seconds slow.", "1 second fast."
String _againstTarget(double pace, int target) {
  final d = (pace - target).round();
  if (d == 0) return 'On target.';
  return '${d.abs()} second${d.abs() == 1 ? '' : 's'} ${d > 0 ? 'slow' : 'fast'}.';
}

/// "1 minute 40 seconds", "1 minute", "30 seconds".
String _spokenTime(int sec) {
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  final mins = sec ~/ 60, secs = sec % 60;
  if (mins == 0) return unit(secs, 'second');
  return secs == 0 ? unit(mins, 'minute') : '${unit(mins, 'minute')} ${unit(secs, 'second')}';
}

/// "400 meters", "1 kilometer", "1.5 kilometers", or a time.
String _spokenTarget(StepTarget t) {
  if (t.isTime) return _spokenTime(t.seconds!);
  final m = t.meters!;
  if (m < 1000) return '$m meters';
  final km = m / 1000;
  return '${km == km.roundToDouble() ? km.toInt() : km} kilometer${km == 1 ? '' : 's'}';
}

/// Something an Interval run says: words, or (with no [text]) a beep of the countdown that ends a time step.
class VoiceCue {
  const VoiceCue(String this.text);
  const VoiceCue.beep() : text = null;
  final String? text;
}

/// The step an Interval run is in, for the recording screen. [reps] is null on a free Interval run; what is left is null on a step with no target.
/// [step] is the plan's Step it runs, null on a free Interval run and after the plan.
class IntervalSnapshot {
  const IntervalSnapshot({required this.kind, this.rep, this.reps, this.step, required this.stepSec, required this.stepMeters, this.secondsLeft, this.metersLeft, required this.planDone});
  final StepKind kind;
  final int? rep, reps;
  final PlanStep? step;
  final int stepSec;
  final double stepMeters;
  final int? secondsLeft;
  final double? metersLeft;
  final bool planDone;
}

/// The kinds of [RecorderEvent]. The strings are what the autosave stores, so they must not change.
class EventKind {
  static const start = 'start', position = 'position', pause = 'pause', resume = 'resume', lap = 'lap', hr = 'hr', next = 'next';
}

/// An input the recorder was given. The log of these is what gets saved while recording: replaying it rebuilds the recorder exactly.
/// Kinds ([EventKind]): `start` (type, id, and an Interval run's plan and planId), `next` (Next or Switch on an Interval run), `position`, `pause`, `resume`, `lap`, `hr` (bpm). Replay ignores kinds it does not know, such as the `steps`
/// and `tick` events of older builds.
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
    this.interval,
  });

  final int elapsedSec; // clock time since the start, pauses included
  final int movingSec; // Moving time
  final double distanceM;
  final bool paused; // Daniel paused it
  final bool autoPaused; // standing still
  final GpsSignal gps;
  final double? currentPaceSecPerKm, avgPaceSecPerKm;
  final int? hr, hrZone; // live beats per minute and its zone (1-5); null when the band is silent
  final IntervalSnapshot? interval; // an Interval run's current step
}

/// A heart-rate reading stands for this long; after it the point or the display has a gap.
const hrStaleSec = 10;

/// The live recording as a pure state machine: fixes and button presses in, a [Recording] out. It never reads a clock; every input carries its time,
/// so tests drive it with fake streams. The platform (GPS, foreground service, autosave) lives in `LiveRecorder`.
class Recorder {
  Recorder._(this.type, this.start, this.sessionId, this.plan, this.planId);

  /// A new recording of [type] ('run' or 'interval') starting at [at]. [sessionId] becomes the Recording's external id.
  /// An Interval run follows [plan] (saved as [planId]); without one it is a free Interval run, switched by hand.
  factory Recorder.start(String type, DateTime at, String sessionId, {IntervalPlan? plan, String? planId}) {
    final r = Recorder._(type, at, sessionId, plan, planId);
    r._log(RecorderEvent(EventKind.start, at, {'type': type, 'id': sessionId, if (plan != null) 'plan': plan.toJson(), 'planId': ?planId}));
    return r;
  }

  /// Rebuilds a recorder from its saved [events] (the first is `start`).
  factory Recorder.replay(List<RecorderEvent> events) {
    final first = events.first;
    final plan = first.data['plan'] as Map?;
    final r = Recorder._(first.data['type'] as String, first.at, first.data['id'] as String, plan == null ? null : IntervalPlan.fromJson(plan.cast()), first.data['planId'] as String?);
    for (final e in events) {
      r._log(e);
    }
    return r;
  }

  final String type;
  final DateTime start;
  final String sessionId;
  final IntervalPlan? plan; // an Interval run's plan, null for a free one and for a Run
  final String? planId;
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

  // Interval run: the steps done and the one in progress.
  final _marks = <StepMark>[];
  final _voice = <VoiceCue>[];
  StepKind _stepKind = StepKind.warmup;
  StepTarget? _stepTarget; // null: the step lasts until Next (open or free) or Finish (after the plan)
  int? _stepRep;
  PlannedStep? _planned; // the plan's step being run
  int _stepIndex = 0; // planned: the step's index in plan.steps
  int _freeReps = 0;
  DateTime _stepAt = DateTime.utc(0);
  double _stepDist = 0, _stepPausedBase = 0;
  int _beeps = 0;
  bool _planDone = false;

  bool get paused => _pausedAt != null;
  bool get isInterval => type == 'interval';

  /// What an Interval run has said so far, in order. A new one appearing is the moment to speak (or beep).
  List<VoiceCue> get voiceCues => List.unmodifiable(_voice);

  /// Next (planned) or Switch (free): ends the current step now and starts the next. Ignored while paused, on a Run, and once the plan is done.
  void next(DateTime at) {
    if (!isInterval || paused || _planDone) return;
    _log(RecorderEvent(EventKind.next, at));
  }

  /// The clock passing on an Interval run: ends a time step even when no fix comes. Not saved; replay reaches the same steps from the next event.
  void tick(DateTime at) {
    if (isInterval && !paused) _advance(at);
  }

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
    if (paused) return; // not recorded, not saved
    _log(RecorderEvent(EventKind.position, s.time, {'lat': s.lat, 'lon': s.lon, 'alt': s.altitude, 'acc': s.accuracy}));
  }

  /// A beats-per-minute reading from the band, [at] when it came. Not recorded while paused.
  void heartRate(int bpm, DateTime at) {
    if (paused) return;
    _log(RecorderEvent(EventKind.hr, at, {'bpm': bpm}));
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
    if (isInterval && !paused && e.kind != EventKind.position) _advance(e.at); // steps that ended before this event end first
    switch (e.kind) {
      case EventKind.start:
        if (isInterval) _openFirstStep(e.at);
      case EventKind.next:
        if (!paused && !_planDone) _reachTarget(e.at, _dist);
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
    if (s.accuracy != null && s.accuracy! > maxAccuracyM) return _advance(s.time);
    final last = _last;
    if (last != null) {
      final dt = s.time.difference(last.time).inMilliseconds / 1000;
      if (dt <= 0) return;
      final step = haversineM(last.lat, last.lon, s.lat, s.lon);
      if (step > maxRunSpeed * max(1, dt)) return _advance(s.time); // a GPS jump
      final before = _dist;
      if (step / dt >= autoPauseSpeed) {
        _dist += step;
        _closeSlow();
        if (!isInterval) _kmCrossings(before, _dist, last.time, dt); // an Interval run has its own cues
      } else {
        _slowSince ??= last.time;
      }
      _advanceOver(last.time, before, s.time, _dist);
    } else {
      _advance(s.time);
    }
    _last = s;
    _t.add(max(0, s.time.difference(start).inMilliseconds / 1000).round());
    _d.add(_dist);
    _lat.add(s.lat);
    _lon.add(s.lon);
    _alt.add(s.altitude);
    _hrCol.add(_bpmAt != null && s.time.difference(_bpmAt!).inSeconds <= hrStaleSec ? _bpm : null);
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

  double _secFrom(DateTime from, DateTime to) => to.difference(from).inMicroseconds / 1e6;

  /// The current step's clock at [at]: time since it began, without Daniel's pauses.
  double _stepClock(DateTime at) => _secFrom(_stepAt, at) - (_pausedSec - _stepPausedBase) - (_pausedAt == null ? 0 : _secFrom(_pausedAt!, at));

  /// When the current time step ends, given no more pauses.
  DateTime _stepEnd() => _stepAt.add(Duration(microseconds: ((_stepTarget!.seconds! + _pausedSec - _stepPausedBase) * 1e6).round()));

  void _openFirstStep(DateTime at) {
    final p = plan;
    if (p == null) return _openStep(StepKind.warmup, null, null, at);
    final first = p.steps.first;
    _openStep(first.kind, first.target, first.rep, at, planned: first);
  }

  void _openStep(StepKind kind, StepTarget? target, int? rep, DateTime at, {String? said, PlannedStep? planned}) {
    _planned = planned;
    _stepKind = kind;
    _stepTarget = target;
    _stepRep = rep;
    _stepAt = at;
    _stepDist = _distAtStepStart ?? _dist;
    _stepPausedBase = _pausedSec;
    _beeps = 0;
    final pace = planned?.step.pace;
    final size = '${target == null ? '' : ', ${_spokenTarget(target)}'}${pace == null ? '' : ', at ${_paceWords(pace)}'}';
    final name = switch (kind) {
      StepKind.warmup => 'Warm-up$size.',
      StepKind.rep => plan == null ? 'Rep $rep.' : 'Rep $rep of ${plan!.reps}$size.',
      StepKind.recovery => 'Recover$size.',
      StepKind.cooldown => 'Cool-down$size.',
    };
    _voice.add(VoiceCue([?said, name].join(' ')));
  }

  double? _distAtStepStart; // the distance where the step being opened begins, when it is not the current distance

  StepMark _markAt(DateTime at, double dist, StepKind kind) =>
      StepMark(kind, _secFrom(start, _stepAt).round(), _secFrom(start, at).round(), _stepClock(at).round(), double.parse((dist - _stepDist).toStringAsFixed(1)));

  /// The current step has reached its target (or Next was pressed) at [at], [dist] meters into the Run: it ends and the next one begins.
  void _reachTarget(DateTime at, double dist) {
    final p = plan;
    if (p != null && _stepIndex == p.steps.length - 1 && _stepKind == StepKind.cooldown) { // the plan's own cool-down: it carries on until Finish
      _planDone = true;
      _stepTarget = null;
      _voice.add(const VoiceCue('Plan done.'));
      return;
    }
    final mark = _markAt(at, dist, _stepKind);
    _marks.add(mark);
    final pace = mark.paceSecPerKm, target = _planned?.step.pace;
    final result = _stepKind == StepKind.rep
        ? 'Rep $_stepRep done. ${_spokenTime(mark.sec)}.${pace == null ? '' : ' ${_spokenPace(pace)}.'}${pace == null || target == null ? '' : ' ${_againstTarget(pace, target)}'}'
        : null;
    _distAtStepStart = dist;
    if (p == null) {
      if (_stepKind == StepKind.rep) {
        _openStep(StepKind.recovery, null, _stepRep, at, said: result);
      } else {
        _freeReps++;
        _openStep(StepKind.rep, null, _freeReps, at, said: result);
      }
    } else if (++_stepIndex < p.steps.length) {
      final s = p.steps[_stepIndex];
      _openStep(s.kind, s.target, s.rep, at, said: result, planned: s);
    } else {
      _planDone = true;
      _openStep(StepKind.cooldown, null, null, at, said: [?result, 'Plan done.'].join(' '));
    }
    _distAtStepStart = null;
  }

  /// Ends every step whose target is reached by [at], with no distance covered since the last fix.
  void _advance(DateTime at) => _advanceOver(at, _dist, at, _dist);

  /// Ends every step whose target is reached while the runner goes from [fromDist] at [from] to [toDist] at [to], at the moment it is reached,
  /// then counts down the last seconds of a time step.
  void _advanceOver(DateTime from, double fromDist, DateTime to, double toDist) {
    if (!isInterval || paused) return;
    final span = _secFrom(from, to);
    double distAt(DateTime t) => span <= 0 ? toDist : fromDist + (toDist - fromDist) * (_secFrom(from, t) / span).clamp(0.0, 1.0);
    while (_stepTarget != null) {
      final target = _stepTarget!;
      if (target.isTime) {
        final end = _stepEnd();
        if (end.isAfter(to)) break;
        _reachTarget(end, distAt(end));
      } else {
        final need = _stepDist + target.meters!;
        if (toDist < need || toDist <= fromDist && fromDist < need) break;
        final when = toDist <= fromDist ? to : from.add(Duration(microseconds: (span * 1e6 * ((need - fromDist) / (toDist - fromDist)).clamp(0.0, 1.0)).round()));
        _reachTarget(when, need);
      }
    }
    if (_stepTarget?.isTime ?? false) {
      final left = _secFrom(to, _stepEnd());
      while (_beeps < 3 && left <= 3 - _beeps) {
        _beeps++;
        _voice.add(const VoiceCue.beep());
      }
    }
  }

  /// The steps as run up to [end], the current one closed there. A free Interval run's recovery after its last rep is its cool-down.
  List<StepMark> _stepsUntil(DateTime end) {
    final all = [..._marks, _markAt(end, _dist, _stepKind)];
    if (plan == null && all.length > 1 && all.last.kind == StepKind.recovery) all[all.length - 1] = all.last.as(StepKind.cooldown);
    return all;
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
    final dist = _dist;
    return RunSnapshot(
      elapsedSec: elapsed.round(),
      movingSec: moving.round(),
      distanceM: dist,
      paused: paused,
      autoPaused: standing,
      gps: gpsSignalOf(_lastSeen, now),
      currentPaceSecPerKm: paused || standing ? null : _currentPace(),
      avgPaceSecPerKm: dist >= 10 && moving > 0 ? moving / (dist / 1000) : null,
      hr: bpm,
      hrZone: bpm == null ? null : zoneOf(bpm, maxHr),
      interval: isInterval ? _intervalSnapshot(now) : null,
    );
  }

  IntervalSnapshot _intervalSnapshot(DateTime now) {
    final t = _stepTarget, clock = _stepClock(now), meters = _dist - _stepDist;
    return IntervalSnapshot(
      kind: _stepKind,
      rep: _stepRep,
      reps: plan?.reps,
      step: _planned?.step,
      stepSec: max(0, clock.round()),
      stepMeters: meters,
      secondsLeft: t?.seconds == null ? null : max(0, (t!.seconds! - clock).round()),
      metersLeft: t?.meters == null ? null : max(0.0, t!.meters! - meters),
      planDone: _planDone,
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
      track: _t.isEmpty ? null : _gpsTrack(isInterval ? _stepsUntil(end) : null),
      planId: planId,
      plan: plan,
    );
  }

  Track _gpsTrack(List<StepMark>? steps) => Track(time: List.of(_t), distance: List.of(_d), lat: List.of(_lat), lon: List.of(_lon), altitude: _alt.any((a) => a != null) ? List.of(_alt) : null, hr: _hrCol.any((h) => h != null) ? List.of(_hrCol) : null, laps: _laps.isEmpty ? null : List.of(_laps), steps: steps);
}
