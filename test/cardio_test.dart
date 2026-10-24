import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/workouts.dart';

void main() {
  group('pace', () {
    test('is duration per km', () {
      expect(paceSecPerKm(5, 1650), 330);
      expect(formatPace(330), '5:30');
      expect(formatPace(359.6), '6:00');
    });
    test('is null without distance', () => expect(paceSecPerKm(0, 600), isNull));
  });

  group('parseDuration', () {
    test('reads m:ss and h:mm:ss', () {
      expect(parseDuration('27:30'), 1650);
      expect(parseDuration('1:02:03'), 3723);
      expect(parseDuration('45'), 2700); // bare number is minutes
    });
    test('rejects junk and bad seconds', () {
      for (final s in ['', 'abc', '5:75', '-3']) {
        expect(parseDuration(s), isNull, reason: s);
      }
    });
  });

  group('validateCardio', () {
    Map<String, String> v(
            {String? type = 'run',
            String km = '5',
            String dur = '27:30',
            String hr = '',
            String incline = '',
            String rpe = ''}) =>
        validateCardio(type: type, distance: km, duration: dur, avgHr: hr, incline: incline, rpe: rpe);

    test('valid input has no errors', () => expect(v(hr: '150', incline: '0', rpe: '7'), isEmpty));
    test('required fields', () {
      expect(v(type: null, km: '', dur: '').keys, containsAll(['type', 'distance', 'duration']));
    });
    test('positive values', () {
      expect(v(km: '0').keys, ['distance']);
      expect(v(km: '-1').keys, ['distance']);
      expect(v(dur: '0:00').keys, ['duration']);
      expect(v(hr: '0').keys, ['avgHr']);
      expect(v(incline: '-2').keys, ['incline']);
    });
    test('RPE is 1-10 whole', () {
      expect(v(rpe: '0').keys, ['rpe']);
      expect(v(rpe: '11').keys, ['rpe']);
      expect(v(rpe: '7.5').keys, ['rpe']);
      expect(v(rpe: '1'), isEmpty);
      expect(v(rpe: '10'), isEmpty);
    });
    test('decimal comma is accepted', () => expect(v(km: '5,2'), isEmpty));
  });

  group('CardioStore', () {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    late AppDb db;
    late CardioStore store;
    var saved = 0;
    setUp(() {
      db = AppDb(NativeDatabase.memory());
      saved = 0;
      store = CardioStore(db, onSaved: () async => saved++);
    });
    tearDown(() => db.close());

    test('save, edit and soft-delete', () async {
      final a = await store.save(type: 'run', startedAt: DateTime(2026, 1, 1), distanceKm: 5, durationSec: 1650, rpe: 7);
      final b = await store.save(type: 'walk', startedAt: DateTime(2026, 1, 3), distanceKm: 3, durationSec: 2400);
      expect([for (final c in await store.watchAll().first) c.id], [b, a]);

      await store.save(
          id: a, type: 'treadmill', startedAt: DateTime(2026, 1, 1), distanceKm: 6, durationSec: 1800, inclinePct: 2);
      final edited = await store.watch(a).first;
      expect((edited.type, edited.distanceKm, edited.inclinePct, edited.rpe, edited.dirty), ('treadmill', 6.0, 2.0, null, 1));

      await store.delete(b);
      expect([for (final c in await store.watchAll().first) c.id], [a]);
      expect(saved, 4);
    });

    test('mergeHistory mixes by date and filters by type', () async {
      final ws = WorkoutStore(db);
      final w = await ws.start();
      await ws.setStartedAt(w, DateTime(2026, 1, 2));
      await ws.finish(w);
      final r1 = await store.save(type: 'run', startedAt: DateTime(2026, 1, 1), distanceKm: 5, durationSec: 1500);
      final r3 = await store.save(type: 'bike', startedAt: DateTime(2026, 1, 3), distanceKm: 20, durationSec: 3600);
      final workouts = await ws.watchHistory().first, cardio = await store.watchAll().first;
      String id(Object o) => o is Workout ? o.id : (o as CardioData).id;

      expect(mergeHistory(workouts, cardio).map(id), [r3, w, r1]);
      expect(mergeHistory(workouts, cardio, cardio: false).map(id), [w]);
      expect(mergeHistory(workouts, cardio, strength: false).map(id), [r3, r1]);
    });
  });

  group('stats', () {
    CardioData c(String id, String type, double km, int sec, int day) => CardioData(
        id: id, createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0,
        type: type, startedAt: DateTime(2026, 1, day), distanceKm: km, durationSec: sec);

    test('bucket is 5 or 10 km within 5%', () {
      expect(distanceBucket(5), 5);
      expect(distanceBucket(4.75), 5);
      expect(distanceBucket(5.25), 5);
      expect(distanceBucket(4.7), isNull);
      expect(distanceBucket(9.6), 10);
      expect(distanceBucket(10.6), isNull);
      expect(distanceBucket(7), isNull);
    });

    final all = [
      c('a', 'run', 10.1, 3000, 4),
      c('b', 'run', 5.1, 1560, 3),
      c('c', 'walk', 5, 3000, 2),
      c('d', 'run', 4.9, 1500, 1),
    ];

    test('filter by type and bucket keeps order', () {
      expect(filterCardio(all, type: 'run').map((s) => s.id), ['a', 'b', 'd']);
      expect(filterCardio(all, bucket: 5).map((s) => s.id), ['b', 'c', 'd']);
      expect(filterCardio(all, type: 'run', bucket: 5).map((s) => s.id), ['b', 'd']);
    });

    test('best time is the shortest duration in the bucket', () {
      expect(bestTime(filterCardio(all, type: 'run'), 5)?.id, 'd');
      expect(bestTime(all, 10)?.id, 'a');
      expect(bestTime(filterCardio(all, type: 'walk'), 10), isNull);
    });

    test('pace series is oldest first in sec/km', () {
      final s = paceSeries([c('x', 'run', 5, 1500, 2), c('y', 'run', 10, 3600, 1)]);
      expect(s, [(DateTime(2026, 1, 1), 360.0), (DateTime(2026, 1, 2), 300.0)]);
    });
  });
}
