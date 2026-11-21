import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_log.dart';

/// A Bluetooth heart-rate band, as found by a scan.
class HrDevice {
  const HrDevice(this.id, this.name);

  final String id; // the Android MAC address
  final String name;

  @override
  bool operator ==(Object other) => other is HrDevice && other.id == id && other.name == name;
  @override
  int get hashCode => Object.hash(id, name);
}

/// The band could not be reached: not advertising, out of range, or held by another app.
class HrNotFound implements Exception {
  const HrNotFound();
}

/// The band refused to stream until it is paired.
class HrPairingRequired implements Exception {
  const HrPairingRequired();
}

/// The phone's Bluetooth. The one platform seam for heart rate; `ble_heart_rate.dart` is the Android adapter.
abstract class HeartRateSensor {
  /// Whether the Bluetooth permissions are already granted, without asking.
  Future<bool> hasPermission();

  /// Asks for them (the system dialog). Call it after explaining why.
  Future<bool> ensurePermission();

  /// Bands advertising the Heart Rate service, found within [timeout].
  Future<List<HrDevice>> scan(Duration timeout);

  /// Connects to [id] and streams beats per minute (about 1 Hz). Errors with [HrNotFound] or [HrPairingRequired]; completes when the link drops.
  Stream<int> subscribe(String id);

  /// Pairs with [id] (the system prompt).
  Future<void> bond(String id);
}

/// The chosen band, remembered between runs. On this phone only.
abstract class HrDeviceMemory {
  Future<HrDevice?> load();
  Future<void> save(HrDevice? device);
}

enum HrLink { off, searching, connected, reconnecting, notFound, needsPairing }

/// Beats per minute from a Heart Rate Measurement packet (characteristic 0x2A37): flags bit 0 picks 8 or 16 bits. Null for no skin contact, 0, or a short packet.
int? parseHeartRate(List<int> d) {
  if (d.isEmpty) return null;
  final flags = d[0];
  final wide = flags & 1 == 1;
  if (d.length < (wide ? 3 : 2)) return null;
  final contactSupported = flags & 4 != 0, contact = flags & 2 != 0;
  if (contactSupported && !contact) return null;
  final bpm = wide ? d[1] | d[2] << 8 : d[1];
  return bpm == 0 ? null : bpm;
}

/// Keeps the app connected to the band for as long as it runs: finds it, remembers it, and reconnects when the stream drops.
/// A drop never throws; the recorder just sees no readings until the link is back. A failed subscribe asks for pairing rather than retrying.
class HeartRateLink extends ChangeNotifier {
  HeartRateLink({
    required this.sensor,
    required this.memory,
    this.onReading,
    this.retry = const Duration(seconds: 5),
    this.scanTimeout = const Duration(seconds: 8),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future.delayed;

  final HeartRateSensor sensor;
  final HrDeviceMemory memory;
  final Duration retry, scanTimeout;
  final Future<void> Function(Duration) _delay;

  /// Called with each beats-per-minute reading.
  void Function(int bpm)? onReading;

  HrLink _state = HrLink.off;
  HrDevice? _device;
  int _gen = 0; // bumped by stop, so a loop that was stopped ends
  bool _connectedOnce = false;
  StreamSubscription<int>? _sub;
  Completer<void>? _done;

  HrLink get state => _state;

  /// The band in use or remembered, once known.
  HrDevice? get device => _device;

  Future<HrDevice?> remembered() async => _device ??= await memory.load();

  /// Starts looking for the band and streaming. Does nothing without the Bluetooth permission.
  void start() {
    _gen++;
    _connectedOnce = false;
    unawaited(_loop(_gen));
  }

  Future<void> stop() async {
    _gen++;
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    await _sub?.cancel();
    _sub = null;
    _set(HrLink.off);
  }

  /// Scans for bands, for the choice on the setup screen.
  Future<List<HrDevice>> scan() async {
    if (!await sensor.ensurePermission()) return const [];
    return sensor.scan(scanTimeout);
  }

  /// Chooses [d] as the band to use from now on.
  Future<void> choose(HrDevice d) async {
    _device = d;
    await memory.save(d);
  }

  Future<void> forget() async {
    _device = null;
    await memory.save(null);
  }

  /// After [HrLink.needsPairing]: pairs, then connects again.
  Future<void> pair() async {
    final d = _device ?? await memory.load();
    if (d == null) return;
    await stop();
    try {
      await sensor.bond(d.id);
    } catch (e, st) {
      reportError('heart_rate_pair', e, st);
    }
    start();
  }

  void _set(HrLink s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  Future<void> _loop(int g) async {
    while (g == _gen) {
      try {
        if (!await sensor.hasPermission()) return _set(HrLink.off);
        var d = _device ??= await memory.load();
        if (d == null) {
          _set(HrLink.searching);
          final found = await sensor.scan(scanTimeout);
          if (g != _gen) return;
          if (found.isEmpty) {
            _set(HrLink.notFound);
            await _delay(retry);
            continue;
          }
          d = found.first;
          await choose(d);
        }
        if (g != _gen) return;
        _set(_connectedOnce ? HrLink.reconnecting : HrLink.searching);
        await _stream(d, g);
        if (g == _gen) _set(HrLink.reconnecting);
      } on HrPairingRequired {
        if (g == _gen) _set(HrLink.needsPairing);
        return;
      } on HrNotFound {
        if (g == _gen) _set(_connectedOnce ? HrLink.reconnecting : HrLink.notFound);
      } catch (e, st) {
        reportError('heart_rate', e, st);
        if (g == _gen) _set(HrLink.reconnecting);
      }
      if (g != _gen) return;
      await _delay(retry);
    }
  }

  Future<void> _stream(HrDevice d, int g) async {
    final done = _done = Completer<void>();
    _sub = sensor.subscribe(d.id).listen(
      (bpm) {
        if (g != _gen) return;
        _connectedOnce = true;
        _set(HrLink.connected);
        onReading?.call(bpm);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    try {
      await done.future;
    } finally {
      await _sub?.cancel();
      _sub = null;
    }
  }
}
