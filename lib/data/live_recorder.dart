import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'cardio.dart';
import 'db.dart';
import 'error_log.dart';
import 'heart_rate.dart';
import 'hr_zones.dart';
import 'recorder.dart';

export 'heart_rate.dart' show HrLink;
export 'recorder.dart' show GpsSignal, PositionSample, RunSnapshot, kmCueText;
export 'stride.dart' show Stride;

/// The app's one recorder, set in main (like `errorLog`). Null in tests that do not record.
LiveRecorder? liveRecorder;

enum PositionPermission { granted, denied, deniedForever, servicesOff }

/// The phone's location sensor. The one platform seam for GPS; see `platform_recording.dart` for the Android adapter.
abstract class PositionSource {
  /// Whether location is already allowed, without asking.
  Future<bool> hasPermission();

  /// Asks for location permission (the system dialog). Call it after explaining why.
  Future<PositionPermission> ensurePermission();

  /// Fixes, about one a second. With [background] false it is only for the GPS indicator before Start.
  Stream<PositionSample> positions({required bool background});
}

/// The phone's step counter, for treadmill recordings. The platform seam for steps; see `platform_recording.dart`.
abstract class StepSource {
  /// Whether activity recognition is already allowed, without asking.
  Future<bool> hasPermission();

  /// Asks for the permission (the system dialog). True when granted.
  Future<bool> ensurePermission();

  /// The step counter's readings: cumulative steps since the phone booted.
  Stream<int> steps();
}

/// The foreground service that keeps the app alive with the screen off, with its ongoing notification.
abstract class RecordingService {
  /// [gps] false for a treadmill recording, which does not use the location permission.
  Future<void> start({bool gps = true});
  Future<void> stop();
}

/// Speaks the km cues. The one platform seam for text to speech; see `platform_recording.dart`.
abstract class SpeechService {
  Future<void> speak(String text);
}

/// The ongoing recording notification: time and distance, and a Pause/Resume button.
abstract class RecordingNotification {
  /// Called with `pause` or `resume` when its button is pressed.
  void Function(String action)? onAction;

  Future<void> update(RunSnapshot s);
  Future<void> clear();
}

/// Where the in-progress recording is saved as it goes: the recorder's event log, in order.
abstract class RecordingJournal {
  Future<void> append(RecorderEvent e);

  /// The unfinished recording's events, empty when there is none.
  Future<List<RecorderEvent>> load();
  Future<void> clear();
}

/// The journal in the local database (`recording_events`, never synced or backed up).
class DbJournal implements RecordingJournal {
  DbJournal(this._db);

  final AppDb _db;

  @override
  Future<void> append(RecorderEvent e) => _db.into(_db.recordingEvents).insert(RecordingEventsCompanion.insert(event: jsonEncode(e.toJson())));

  @override
  Future<List<RecorderEvent>> load() async {
    final rows = await (_db.select(_db.recordingEvents)..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
    return [for (final r in rows) RecorderEvent.fromJson((jsonDecode(r.event) as Map).cast<String, Object?>())];
  }

  @override
  Future<void> clear() => _db.delete(_db.recordingEvents).go();
}

/// The recording in progress: wires a [Recorder] to the location source, the foreground service, the autosave and the Run store.
/// One per app. Listen for changes; the screen reads [snapshot] on its own 1 s timer, since time passes between fixes.
class LiveRecorder extends ChangeNotifier {
  LiveRecorder({required this.source, required this.service, required this.journal, required this.cardio, this.speech, this.notification, this.stepSource, this.heartRate, this.maxHr, DateTime Function()? now}) : _now = now ?? DateTime.now {
    notification?.onAction = (a) => a == 'resume' ? resume() : pause();
    heartRate?.onReading = _onHeartRate;
    heartRate?.addListener(notifyListeners);
  }

  final PositionSource source;
  final RecordingService service;
  final RecordingJournal journal;
  final CardioStore cardio;

  /// The Bluetooth heart-rate band, null when the phone has none wired (tests). Runs only while a recording runs.
  final HeartRateLink? heartRate;

  /// The Max HR in force, for the zone. Defaults to [defaultMaxHr].
  final int Function()? maxHr;
  final SpeechService? speech;
  final RecordingNotification? notification;
  final StepSource? stepSource; // null where there is no step counter (tests)
  final DateTime Function() _now;

  Recorder? _rec;
  Timer? _noteTimer;
  StreamSubscription<Object?>? _sub;
  int _finishedSteps = 0;
  PositionSample? _lastSeen;
  Future<void> _queue = Future.value();

  /// True while a recording exists, running or paused.
  bool get active => _rec != null;
  String? get type => _rec?.type;
  int get lapCount => _rec?.laps.length ?? 0;

  /// The recording's numbers now, null when nothing is being recorded.
  RunSnapshot? get snapshot => _rec?.snapshot(_now(), maxHr: maxHr?.call() ?? defaultMaxHr);

  /// State of the heart-rate link.
  HrLink get hrState => heartRate?.state ?? HrLink.off;

  /// Signal of the latest fix, also before Start.
  GpsSignal get gps => gpsSignalOf(_lastSeen, _now());

  /// Steps of the treadmill recording that [finish] last saved.
  int get finishedSteps => _finishedSteps;

  Future<bool> hasStepPermission() async => await stepSource?.hasPermission() ?? false;
  Future<bool> requestStepPermission() async => await stepSource?.ensurePermission() ?? false;

  Future<PositionPermission> requestPermission() => source.ensurePermission();
  Future<bool> hasPermission() => source.hasPermission();

  /// Starts listening for fixes so the GPS indicator works before Start. Needs the permission.
  Future<void> open() async => _listen(background: false);

  /// Stops the GPS indicator's listening. Does nothing to a recording.
  Future<void> close() async {
    if (_rec == null) await _stopListening();
  }

  /// [strideM] is the calibrated stride a treadmill recording measures distance with.
  Future<void> start(String type, {double? strideM}) async {
    if (_rec != null) return;
    final rec = Recorder.start(type, _now(), const Uuid().v4(), strideM: strideM);
    _rec = rec;
    _save(rec.events.last);
    await service.start(gps: !rec.isTreadmill);
    await _listen(background: true);
    heartRate?.start();
    _startNotifying();
    notifyListeners();
  }

  void pause() {
    _act((r, at) => r.pause(at));
    refreshNotification();
  }

  /// Marks a lap now.
  void lap() => _act((r, at) => r.lap(at));

  /// Puts the current time, distance and pause state in the notification.
  void refreshNotification() {
    final s = snapshot;
    if (s != null) notification?.update(s);
  }

  Future<void> resume() async {
    if (_rec == null) return;
    await service.start(gps: !_rec!.isTreadmill); // after a restart the service is not running yet
    if (_sub == null || !_background) await _listen(background: true);
    if (hrState == HrLink.off) heartRate?.start();
    _act((r, at) => r.resume(at));
    _startNotifying();
  }

  void _startNotifying() {
    _noteTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => refreshNotification());
    refreshNotification();
  }

  /// Saves the Run through ingest (so a later Fitbit session merges into it) and returns its id.
  Future<String?> finish() async {
    final rec = _rec;
    if (rec == null) return null;
    final recording = rec.finish(_now());
    await heartRate?.stop();
    _finishedSteps = rec.steps;
    await _stopListening();
    _stopNotification();
    await service.stop();
    await flush();
    final result = await cardio.ingest(recording);
    await journal.clear();
    _rec = null;
    notifyListeners();
    return result.id;
  }

  /// Drops the recording: nothing is saved.
  Future<void> discard() async {
    if (_rec == null) return;
    await heartRate?.stop();
    await _stopListening();
    _stopNotification();
    await service.stop();
    await flush();
    await journal.clear();
    _rec = null;
    notifyListeners();
  }

  void _stopNotification() {
    _noteTimer?.cancel();
    _noteTimer = null;
    notification?.clear();
  }

  /// Picks up a recording the app was killed in, as paused at its last point. True when there was one. Call once at startup.
  Future<bool> restore() async {
    final events = await journal.load();
    if (events.isEmpty || events.first.kind != EventKind.start) return false;
    final rec = Recorder.replay(events);
    if (!rec.paused) {
      rec.pause(rec.lastEventAt);
      _save(rec.events.last);
    }
    _rec = rec;
    if (!rec.isTreadmill) await _listen(background: false); // a treadmill recording listens again on Resume
    notifyListeners();
    return true;
  }

  /// Completes when everything is saved.
  Future<void> flush() => _queue;

  bool _background = false;

  Future<void> _listen({required bool background}) async {
    await _stopListening();
    _background = background;
    if (_rec?.isTreadmill ?? false) {
      _sub = stepSource?.steps().listen(_onSteps, onError: (Object e, StackTrace st) => reportError('steps', e, st));
      return;
    }
    _sub = source.positions(background: background).listen(_onSample, onError: (Object e, StackTrace st) => reportError('location', e, st));
  }

  Future<void> _stopListening() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }

  void _onSample(PositionSample s) {
    _lastSeen = s;
    _input((r, _) => r.position(s));
  }

  void _onHeartRate(int bpm) => _input((r, at) => r.heartRate(bpm, at));

  void _onSteps(int count) => _input((r, at) => r.stepCount(at, count));

  void _act(void Function(Recorder, DateTime) f) => _input(f);

  /// Gives the recorder one input: saves the event it logged, speaks any km it completed, and notifies. Before Start there is no recorder, so only the notify.
  void _input(void Function(Recorder, DateTime) f) {
    final rec = _rec;
    if (rec != null) {
      final before = rec.events.length, cues = rec.kmCues.length;
      f(rec, _now());
      if (rec.events.length > before) _save(rec.events.last);
      for (final c in rec.kmCues.skip(cues)) {
        speech?.speak(kmCueText(c)).catchError((Object e, StackTrace st) => reportError('km_voice', e, st));
      }
    }
    notifyListeners();
  }

  /// Autosave: appended in order, one at a time, as events arrive.
  void _save(RecorderEvent e) {
    _queue = _queue.then((_) => journal.append(e)).catchError((Object err, StackTrace st) => reportError('recording_autosave', err, st));
  }
}
