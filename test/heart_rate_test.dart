import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/heart_rate.dart';
import 'package:timburr/data/live_recorder.dart';
import 'package:timburr/data/recorder.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';

final t0 = DateTime.utc(2026, 11, 10, 7);
DateTime at(int sec) => t0.add(Duration(seconds: sec));
PositionSample fix(int sec) => PositionSample(time: at(sec), lat: 32.0 + sec * 3.0 / 111195, lon: 34.8, accuracy: 5);

class FakePositions implements PositionSource {
  final _c = StreamController<PositionSample>.broadcast();
  @override
  Stream<PositionSample> positions({required bool background}) => _c.stream;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<PositionPermission> ensurePermission() async => PositionPermission.granted;
  void emit(PositionSample s) => _c.add(s);
}

class FakeService implements RecordingService {
  @override
  Future<void> start({bool gps = true}) async {}
  @override
  Future<void> stop() async {}
}

class MemoryDevice implements HrDeviceMemory {
  HrDevice? saved;
  @override
  Future<HrDevice?> load() async => saved;
  @override
  Future<void> save(HrDevice? d) async => saved = d;
}

/// A band: each subscribe gets a controller the test feeds, closes or fails.
class FakeBand implements HeartRateSensor {
  FakeBand({this.found = const []});
  List<HrDevice> found;
  bool permitted = true;
  final subscribed = <String>[];
  final bonded = <String>[];
  final attempts = <StreamController<int>>[];
  Object? failNext; // delivered by the next subscribe as an error on its stream
  int scans = 0;

  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<bool> ensurePermission() async => permitted;
  @override
  Future<List<HrDevice>> scan(Duration timeout) async {
    scans++;
    return found;
  }

  @override
  Stream<int> subscribe(String id) {
    subscribed.add(id);
    final c = StreamController<int>();
    attempts.add(c);
    final f = failNext;
    failNext = null;
    if (f != null) scheduleMicrotask(() => c.addError(f));
    return c.stream;
  }

  @override
  Future<void> bond(String id) async => bonded.add(id);
}

const air = HrDevice('AA:01', 'Fitbit Air');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('parseHeartRate', () {
    test('reads the 8-bit and the 16-bit value by the format flag', () {
      expect(parseHeartRate([0x00, 142]), 142);
      expect(parseHeartRate([0x01, 0x2C, 0x01]), 300);
    });
    test('is null for no contact, for zero and for a short packet', () {
      expect(parseHeartRate([0x04, 142]), isNull); // contact supported, not detected
      expect(parseHeartRate([0x06, 142]), 142); // contact detected
      expect(parseHeartRate([0x00, 0]), isNull);
      expect(parseHeartRate([0x01, 5]), isNull);
      expect(parseHeartRate(const []), isNull);
    });
  });

  group('Recorder heart rate', () {
    test('stores a reading per point and leaves a gap where the link was silent for over 10 s', () {
      final r = Recorder.start('run', at(0), 's');
      for (var s = 0; s <= 40; s++) {
        if (s < 15 || s > 28) r.heartRate(150, at(s)); // the band drops from 15 to 28
        r.position(fix(s));
      }
      final hr = r.finish(at(40)).track!.hr!;
      expect(hr.length, 41);
      expect(hr[10], 150);
      expect(hr[20], 150); // a reading from 14 s still stands for 10 s
      expect(hr[26], isNull);
      expect(hr[35], 150);
    });

    test('a track without any reading has no heart rate column', () {
      final r = Recorder.start('run', at(0), 's');
      for (var s = 0; s <= 5; s++) {
        r.position(fix(s));
      }
      expect(r.finish(at(5)).track!.hr, isNull);
    });

    test('the snapshot shows the live reading and its zone, and nothing once stale', () {
      final r = Recorder.start('run', at(0), 's');
      r.heartRate(171, at(5));
      expect(r.snapshot(at(6), maxHr: 190).hr, 171);
      expect(r.snapshot(at(6), maxHr: 190).hrZone, 5);
      expect(r.snapshot(at(6), maxHr: 200).hrZone, 4);
      expect(r.snapshot(at(20), maxHr: 190).hr, isNull);
      expect(r.snapshot(at(20), maxHr: 190).hrZone, isNull);
    });

    test('replaying the saved events rebuilds the heart rate', () {
      final r = Recorder.start('run', at(0), 's');
      for (var s = 0; s <= 5; s++) {
        r.heartRate(140 + s, at(s));
        r.position(fix(s));
      }
      final copy = Recorder.replay(r.events.map((e) => RecorderEvent.fromJson(e.toJson())).toList());
      expect(copy.finish(at(5)).track!.hr, [140, 141, 142, 143, 144, 145]);
    });

    test('a treadmill run, which has no fixes, still gets a track of heart rate', () {
      final r = Recorder.start('treadmill', at(0), 's');
      for (var s = 0; s < 5; s++) {
        r.heartRate(130 + s, at(s));
      }
      final t = r.finish(at(5)).track!;
      expect(t.hr, [130, 131, 132, 133, 134]);
      expect(t.time, [0, 1, 2, 3, 4]);
      expect(t.lat, isNull);
    });

    test('readings while paused are not recorded', () {
      final r = Recorder.start('run', at(0), 's');
      r.pause(at(1));
      r.heartRate(150, at(2));
      expect(r.events.where((e) => e.kind == 'hr'), isEmpty);
    });
  });

  group('HeartRateLink', () {
    late FakeBand band;
    late MemoryDevice memory;
    late List<int> readings;
    late HeartRateLink link;

    setUp(() {
      band = FakeBand(found: [air]);
      memory = MemoryDevice();
      readings = [];
      link = HeartRateLink(sensor: band, memory: memory, onReading: readings.add, delay: (d) => Future.delayed(Duration.zero));
    });

    test('finds the band, remembers it and shows readings', () async {
      link.start();
      await pumpEventQueue();
      expect(memory.saved, air);
      expect(band.subscribed, ['AA:01']);
      band.attempts.single.add(140);
      await pumpEventQueue();
      expect(link.state, HrLink.connected);
      expect(readings, [140]);
      await link.stop();
    });

    test('uses the remembered band without scanning', () async {
      memory.saved = air;
      link.start();
      await pumpEventQueue();
      expect(band.scans, 0);
      expect(band.subscribed, ['AA:01']);
      await link.stop();
    });

    test('a dropped connection reconnects on its own and keeps reading', () async {
      memory.saved = air;
      link.start();
      await pumpEventQueue();
      band.attempts[0].add(140);
      await band.attempts[0].close(); // the band went silent
      await pumpEventQueue();
      expect(link.state, HrLink.reconnecting);
      expect(band.subscribed, ['AA:01', 'AA:01']);
      band.attempts[1].add(150);
      await pumpEventQueue();
      expect(readings, [140, 150]);
      expect(link.state, HrLink.connected);
      await link.stop();
    });

    test('a band that is not found is retried and reported as not found', () async {
      band.found = [];
      link.start();
      await pumpEventQueue();
      expect(link.state, HrLink.notFound);
      expect(band.scans, greaterThan(1)); // keeps looking
      band.found = [air];
      await pumpEventQueue();
      expect(memory.saved, air);
      await link.stop();
    });

    test('a failed subscribe asks for pairing instead of retrying', () async {
      memory.saved = air;
      band.failNext = const HrPairingRequired();
      link.start();
      await pumpEventQueue();
      expect(link.state, HrLink.needsPairing);
      expect(band.subscribed, hasLength(1));
      await link.pair(); // bonds, then connects again
      await pumpEventQueue();
      expect(band.bonded, ['AA:01']);
      expect(band.subscribed, hasLength(2));
      await link.stop();
    });

    test('stays off without Bluetooth permission', () async {
      band.permitted = false;
      link.start();
      await pumpEventQueue();
      expect(link.state, HrLink.off);
      expect(band.scans, 0);
    });

    test('forgetting the band clears the memory', () async {
      memory.saved = air;
      await link.forget();
      expect(memory.saved, isNull);
    });
  });

  group('LiveRecorder with a band', () {
    late AppDb db;
    late CardioStore cardio;
    late FakePositions source;
    late FakeBand band;
    late MemoryDevice memory;
    var now = t0;
    LiveRecorder make() => LiveRecorder(
          source: source,
          service: FakeService(),
          journal: DbJournal(db),
          cardio: cardio,
          now: () => now,
          heartRate: HeartRateLink(sensor: band, memory: memory, delay: (_) => Future.delayed(Duration.zero)),
          maxHr: () => 190,
        );

    setUp(() {
      db = AppDb(NativeDatabase.memory());
      cardio = CardioStore(db);
      source = FakePositions();
      band = FakeBand(found: [air]);
      memory = MemoryDevice()..saved = air;
      now = t0;
    });
    tearDown(() => db.close());

    test('a run with a dropped band is saved with heart rate gaps, which Health Connect then fills', () async {
      final rec = make();
      await rec.start('run');
      await pumpEventQueue();
      for (var s = 0; s <= 60; s++) {
        now = at(s);
        if (s == 20) {
          await band.attempts[0].close(); // the band drops; the link reconnects
          await pumpEventQueue();
        }
        if (s < 20) band.attempts[0].add(150);
        if (s > 45) band.attempts.last.add(155);
        await pumpEventQueue();
        source.emit(fix(s));
        await pumpEventQueue();
      }
      expect(rec.snapshot!.hr, 155);
      expect(rec.snapshot!.hrZone, 4); // 155 of 190 is 82%
      now = at(60);
      final id = (await rec.finish())!;
      expect(rec.hrState, HrLink.off);
      final hr = (await cardio.watchTrack(id).first)!.hr!;
      expect(hr[10], 150);
      expect(hr[40], isNull); // the gap
      expect(hr[55], 155);
      final fromBand = Recording(
        source: 'health_connect', type: 'run', start: at(0), elapsedSec: 60, movingSec: 60, externalId: 'h',
        track: Track(time: [for (var i = 0; i <= 60; i++) i], hr: [for (var i = 0; i <= 60; i++) 120]),
      );
      await cardio.ingest(fromBand);
      final filled = (await cardio.watchTrack(id).first)!.hr!;
      expect(filled[10], 150);
      expect(filled[40], 120);
    });
  });
}
