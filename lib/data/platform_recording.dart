import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// Android adapter for [StepSource]: the phone's step counter through the pedometer plugin. No logic here; checked on the phone.
class PedometerSource implements StepSource {
  @override
  Future<bool> hasPermission() => Permission.activityRecognition.isGranted;

  @override
  Future<bool> ensurePermission() async => (await Permission.activityRecognition.request()).isGranted;

  @override
  Stream<int> steps() => Pedometer.stepCountStream.map((e) => e.steps);
}

/// Android adapter for [RecordingService]: a location-type foreground service with an ongoing notification and a wake lock,
/// so recording continues with the screen off. It runs no task of its own; the recorder stays in the app's isolate.
class ForegroundRecordingService implements RecordingService {
  bool _ready = false;

  void _init() {
    if (_ready) return;
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
  Future<void> start({bool gps = true}) async {
    _init();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceTypes: [gps ? ForegroundServiceTypes.location : ForegroundServiceTypes.health],
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
