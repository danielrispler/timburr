import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/treadmill.dart';

void main() {
  late AppDb db;
  late CardioStore store;
  var day = 0;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
    day = 0;
  });
  tearDown(() => db.close());

  /// A Run on the next day: [km] in [sec]; [corrected] marks the distance as typed by Daniel.
  Future<void> add(String type, double km, int sec, {bool corrected = true, bool deleted = false}) async {
    day++;
    final id = await store.save(type: type, startedAt: DateTime.utc(2026, 1, day), distanceKm: km, durationSec: sec);
    if (corrected) await store.edit(id, {'distance_km': km});
    if (deleted) await store.delete(id);
  }

  Future<double> pace() async => usualTreadmillPace(await db.select(db.cardio).get());

  group('usualTreadmillPace', () {
    test('is 6:00 per km with no corrected treadmill Run', () async {
      expect(await pace(), 360);
      await add('treadmill', 5, 1500, corrected: false); // the estimate itself must not feed the next estimate
      await add('run', 5, 1200);
      expect(await pace(), 360);
    });

    test('is the median pace of the corrected treadmill Runs', () async {
      await add('treadmill', 5, 1500); // 300
      await add('treadmill', 5, 1800); // 360
      await add('treadmill', 5, 2100); // 420
      expect(await pace(), 360);
      await add('treadmill', 5, 1650); // 330: an even count takes the middle two
      expect(await pace(), closeTo(345, 1e-9));
    });

    test('ignores deleted Runs and outdoor Runs', () async {
      await add('treadmill', 5, 1500);
      await add('treadmill', 5, 3000, deleted: true);
      await add('run', 5, 1000);
      expect(await pace(), 300);
    });

    test('looks only at the latest ten', () async {
      for (var i = 0; i < 5; i++) {
        await add('treadmill', 5, 3000); // old and slow: 600
      }
      for (var i = 0; i < 10; i++) {
        await add('treadmill', 5, 1500);
      }
      expect(await pace(), 300);
    });
  });

  group('treadmillEdits', () {
    const initial = {'distance_km': '5.00', 'duration_sec': '25:00', 'incline_pct': '', 'steps': '', 'calories': '380'};

    test('keeps only the fields that were changed and parse', () {
      expect(treadmillEdits(initial, initial), isEmpty);
      expect(
        treadmillEdits(initial, {'distance_km': '4,8', 'duration_sec': '24:30', 'incline_pct': '2', 'steps': '6100', 'calories': '380'}),
        {'distance_km': 4.8, 'duration_sec': 1470, 'incline_pct': 2.0, 'steps': 6100},
      );
      expect(treadmillEdits(initial, {...initial, 'steps': 'lots', 'incline_pct': ' '}), isEmpty);
    });
  });
}
