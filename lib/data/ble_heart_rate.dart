import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'heart_rate.dart';

final _hrService = Guid('180D'), _hrMeasurement = Guid('2A37');

/// Android adapter for [HeartRateSensor]: flutter_blue_plus over the standard Heart Rate Profile. No logic here beyond the connection; checked on the phone.
class BleHeartRateSensor implements HeartRateSensor {
  @override
  Future<bool> hasPermission() async => await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;

  @override
  Future<bool> ensurePermission() async {
    // The plugin asks for the Bluetooth permissions when it first scans.
    try {
      await FlutterBluePlus.startScan(withServices: [_hrService], timeout: const Duration(seconds: 1));
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    var state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
      state = await FlutterBluePlus.adapterState.first;
    }
    return state == BluetoothAdapterState.on;
  }

  @override
  Future<List<HrDevice>> scan(Duration timeout) async {
    await FlutterBluePlus.startScan(withServices: [_hrService], timeout: timeout);
    await FlutterBluePlus.isScanning.where((s) => !s).first;
    return [
      for (final r in FlutterBluePlus.lastScanResults)
        HrDevice(r.device.remoteId.str, r.device.platformName.isEmpty ? r.advertisementData.advName : r.device.platformName),
    ];
  }

  @override
  Stream<int> subscribe(String id) {
    final device = BluetoothDevice.fromId(id);
    StreamSubscription<List<int>>? values;
    StreamSubscription<BluetoothConnectionState>? link;
    late final StreamController<int> out;
    out = StreamController<int>(
      onListen: () async {
        try {
          try {
            await device.connect(timeout: const Duration(seconds: 12), mtu: null);
          } catch (_) {
            throw const HrNotFound(); // not advertising, out of range, or held by another app
          }
          link = device.connectionState.listen((s) {
            if (s == BluetoothConnectionState.disconnected && !out.isClosed) out.close();
          });
          final c = await _hrCharacteristic(device);
          if (c == null) throw const HrNotFound(); // connected, but the band isn't sharing heart rate
          try {
            await c.setNotifyValue(true);
            values = c.onValueReceived.listen((v) {
              final bpm = parseHeartRate(v);
              if (bpm != null && !out.isClosed) out.add(bpm);
            });
          } catch (_) {
            throw const HrPairingRequired(); // the band did not let us subscribe: it wants pairing first
          }
        } catch (e, st) {
          if (!out.isClosed) {
            out.addError(e, st);
            await out.close();
          }
        }
      },
      onCancel: () async {
        await values?.cancel();
        await link?.cancel();
        try {
          await device.disconnect();
        } catch (_) {}
      },
    );
    return out.stream;
  }

  /// The Heart Rate Measurement characteristic, or null when the band doesn't offer it.
  /// The Air is already connected through the Fitbit app, so Android may answer from a service list cached before
  /// Share heart rate was turned on; clear that cache and look again once.
  Future<BluetoothCharacteristic?> _hrCharacteristic(BluetoothDevice device) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        try {
          await device.clearGattCache();
        } catch (_) {}
      }
      final services = await device.discoverServices();
      debugPrint('[HR] ${device.remoteId} services: ${[for (final s in services) s.uuid.str]}'); // one line in logcat for phone debugging
      for (final s in services.where((s) => s.uuid == _hrService)) {
        for (final c in s.characteristics.where((c) => c.uuid == _hrMeasurement)) {
          return c;
        }
      }
    }
    return null;
  }

  @override
  Future<void> bond(String id) => BluetoothDevice.fromId(id).createBond();
}

/// The chosen band, in a small file next to the app's data (this phone only).
class FileDeviceMemory implements HrDeviceMemory {
  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/heart_rate_band.json');

  @override
  Future<HrDevice?> load() async {
    try {
      final j = jsonDecode(await (await _file()).readAsString()) as Map;
      return HrDevice(j['id'] as String, j['name'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(HrDevice? device) async {
    final f = await _file();
    if (device == null) {
      if (await f.exists()) await f.delete();
    } else {
      await f.writeAsString(jsonEncode({'id': device.id, 'name': device.name}));
    }
  }
}
