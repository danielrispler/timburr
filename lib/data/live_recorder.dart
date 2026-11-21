import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'cardio.dart';
import 'db.dart';
import 'error_log.dart';
import 'recorder.dart';

export 'recorder.dart' show GpsSignal, PositionSample, RunSnapshot;

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

/// The foreground service that keeps the app alive with the screen off, with its ongoing notification.
/// shortcut for #69: add an `update(RunSnapshot)` here for the notification's time, distance and pause button.
abstract class RecordingService {
  Future<void> start();
  Future<void> stop();
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
  LiveRecorder({required this.source, required this.service, required this.journal, required this.cardio, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PositionSource source;
  final RecordingService service;
  final RecordingJournal journal;
  final CardioStore cardio;
  final DateTime Function() _now;

  Recorder? _rec;
  StreamSubscription<PositionSample>? _sub;
  PositionSample? _lastSeen;
  Future<void> _queue = Future.value();

  /// True while a recording exists, running or paused.
  bool get active => _rec != null;
  String? get type => _rec?.type;

  /// The recording's numbers now, null when nothing is being recorded.
  RunSnapshot? get snapshot => _rec?.snapshot(_now());

  /// Signal of the latest fix, also before Start.
  GpsSignal get gps => gpsSignalOf(_lastSeen, _now());

  Future<PositionPermission> requestPermission() => source.ensurePermission();
  Future<bool> hasPermission() => source.hasPermission();

  /// Starts listening for fixes so the GPS indicator works before Start. Needs the permission.
  Future<void> open() async => _listen(background: false);

  /// Stops the GPS indicator's listening. Does nothing to a recording.
  Future<void> close() async {
    if (_rec == null) await _stopListening();
  }

  Future<void> start(String type) async {
    if (_rec != null) return;
    final rec = Recorder.start(type, _now(), const Uuid().v4());
    _rec = rec;
    _save(rec.events.last);
    await service.start();
    await _listen(background: true);
    notifyListeners();
  }

  void pause() => _act((r, at) => r.pause(at));

  Future<void> resume() async {
    if (_rec == null) return;
    await service.start(); // after a restart the service is not running yet
    if (_sub == null || !_background) await _listen(background: true);
    _act((r, at) => r.resume(at));
  }

  /// Saves the Run through ingest (so a later Fitbit session merges into it) and returns its id.
  Future<String?> finish() async {
    final rec = _rec;
    if (rec == null) return null;
    final recording = rec.finish(_now());
    await _stopListening();
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
    await _stopListening();
    await service.stop();
    await flush();
    await journal.clear();
    _rec = null;
    notifyListeners();
  }

  /// Picks up a recording the app was killed in, as paused at its last point. True when there was one. Call once at startup.
  Future<bool> restore() async {
    final events = await journal.load();
    if (events.isEmpty || events.first.kind != 'start') return false;
    final rec = Recorder.replay(events);
    if (!rec.paused) {
      rec.pause(rec.lastEventAt);
      _save(rec.events.last);
    }
    _rec = rec;
    await _listen(background: false);
    notifyListeners();
    return true;
  }

  /// Completes when everything is saved.
  Future<void> flush() => _queue;

  bool _background = false;

  Future<void> _listen({required bool background}) async {
    await _stopListening();
    _background = background;
    _sub = source.positions(background: background).listen(_onSample, onError: (Object e, StackTrace st) => reportError('location', e, st));
  }

  Future<void> _stopListening() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }

  void _onSample(PositionSample s) {
    _lastSeen = s;
    final rec = _rec;
    if (rec != null) {
      final before = rec.events.length;
      rec.position(s);
      if (rec.events.length > before) _save(rec.events.last);
    }
    notifyListeners();
  }

  void _act(void Function(Recorder, DateTime) f) {
    final rec = _rec;
    if (rec == null) return;
    final before = rec.events.length;
    f(rec, _now());
    if (rec.events.length > before) _save(rec.events.last);
    notifyListeners();
  }

  /// Autosave: appended in order, one at a time, as events arrive.
  void _save(RecorderEvent e) {
    _queue = _queue.then((_) => journal.append(e)).catchError((Object err, StackTrace st) => reportError('recording_autosave', err, st));
  }
}
