import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

import 'cardio.dart';
import 'live_recorder.dart';

/// Android adapter for [PositionSource]: the geolocator plugin (Fused Location). No logic here; checked on the phone.
class GeolocatorSource implements PositionSource {
  @override
  Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return (p == LocationPermission.always || p == LocationPermission.whileInUse) && await Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<PositionPermission> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return PositionPermission.servicesOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    // The foreground service's notification needs this on Android 13+. Declining it does not stop the recording.
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    return switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => PositionPermission.granted,
      LocationPermission.deniedForever => PositionPermission.deniedForever,
      _ => PositionPermission.denied,
    };
  }

  @override
  Stream<PositionSample> positions({required bool background}) => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(accuracy: LocationAccuracy.best, distanceFilter: 0, intervalDuration: const Duration(seconds: 1)),
      ).map((p) => PositionSample(time: p.timestamp, lat: p.latitude, lon: p.longitude, altitude: p.altitude, accuracy: p.accuracy));
}

/// Android adapter for [RecordingService]: a location-type foreground service with an ongoing notification and a wake lock,
/// so recording continues with the screen off. It runs no task of its own; the recorder stays in the app's isolate.
class ForegroundRecordingService implements RecordingService, RecordingNotification {
  bool _ready = false;

  @override
  void Function(String action)? onAction;

  /// The service's task relays the notification button presses to the app.
  void _onTaskData(Object data) {
    if (data is String) onAction?.call(data);
  }

  bool _paused = false;

  List<NotificationButton> get _buttons => [NotificationButton(id: _paused ? 'resume' : 'pause', text: _paused ? 'Resume' : 'Pause')];

  @override
  Future<void> update(RunSnapshot s) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    final km = (s.distanceM / 1000).toStringAsFixed(2);
    _paused = s.paused;
    await FlutterForegroundTask.updateService(
      notificationTitle: s.paused ? 'Run paused' : 'Recording run',
      notificationText: '${formatDuration(s.movingSec)} · $km km',
      notificationButtons: _buttons,
    );
  }

  @override
  Future<void> clear() async => FlutterForegroundTask.removeTaskDataCallback(_onTaskData);

  void _init() {
    if (_ready) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'timburr_recording',
        channelName: 'Run recording',
        channelDescription: 'Shown while Timburr records a run.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing(), allowWakeLock: true, allowAutoRestart: false),
    );
    _ready = true;
  }

  @override
  Future<void> start() async {
    _init();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    if (await FlutterForegroundTask.isRunningService) return;
    _paused = false;
    await FlutterForegroundTask.startService(
      notificationButtons: _buttons,
      callback: recordingTaskCallback,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'Recording run',
      notificationText: 'Tap to return to Timburr',
    );
  }

  @override
  Future<void> stop() async {
    _init();
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }
}

/// Runs in the foreground service's isolate: passes a notification button press to the app.
@pragma('vm:entry-point')
void recordingTaskCallback() => FlutterForegroundTask.setTaskHandler(_ButtonRelay());

class _ButtonRelay extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);
}

/// Android adapter for [SpeechService]: the system text to speech, spoken over music (ducking is up to the system).
class TtsSpeech implements SpeechService {
  final _tts = FlutterTts();

  @override
  Future<void> speak(String text) => _tts.speak(text);
}
