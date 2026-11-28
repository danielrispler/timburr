import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/running.dart';
import 'package:timburr/data/shoes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDb db;
  late CardioStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
  });
  tearDown(() => db.close());

  Future<CardioData> run(String id, {double km = 5, String type = 'run', String? route, DateTime? deleted}) async {
    await db.save(db.cardio, {'id': id, 'type': type, 'started_at': DateTime(2026, 11, 1), 'distance_km': km, 'duration_sec': 1500, 'route': route, 'deleted_at': deleted});
    return (await store.watch(id).first);
  }

  group('shoe totals', () {
    test('sum the live Runs on each shoe, ignoring other shoes, no shoe and deleted Runs', () async {
      final a = await store.shoes.add('Pegasus'), b = await store.shoes.add('Ghost');
      await run('r1', km: 5);
      await run('r2', km: 10.5);
      await run('r3', km: 8);
      await run('r4', km: 3);
      await run('r5', km: 100, deleted: DateTime(2026, 11, 2));
      await run('r6', km: 7, type: 'interval');
      await store.edit('r1', {'shoe_id': a});
      await store.edit('r2', {'shoe_id': a});
      await store.edit('r3', {'shoe_id': b});
      await store.edit('r5', {'shoe_id': a});
      await store.edit('r6', {'shoe_id': b});
      final totals = shoeTotals(await store.watchAll().first);
      expect(totals, {a: 15.5, b: 15.0});
      expect(totals[b] ?? 0, 15.0);
    });

    test('a Run with no distance adds nothing, and no Runs gives an empty map', () async {
      final a = await store.shoes.add('Pegasus');
      expect(shoeTotals(const []), isEmpty);
      await db.save(db.cardio, {'id': 'r1', 'type': 'run', 'started_at': DateTime(2026, 11, 1), 'duration_sec': 60, 'shoe_id': a});
      expect(shoeTotals(await store.watchAll().first), {a: 0.0});
    });
  });

  group('shoe store', () {
    test('adds, trims the name, and rejects an empty one', () async {
      final id = await store.shoes.add('  Pegasus ');
      expect((await store.shoes.watchAll().first).single, isA<Shoe>().having((s) => s.id, 'id', id).having((s) => s.name, 'name', 'Pegasus'));
      expect(() => store.shoes.add('   '), throwsArgumentError);
    });

    test('only one default; retiring drops it, and in-use shoes list before retired ones', () async {
      final a = await store.shoes.add('B shoe'), b = await store.shoes.add('A shoe'), c = await store.shoes.add('C shoe');
      await store.shoes.setDefault(a);
      await store.shoes.setDefault(b);
      expect((await store.shoes.watchAll().first).where((s) => s.isDefault).map((s) => s.id), [b]);
      expect(await store.shoes.defaultId(), b);
      await store.shoes.setRetired(b, true);
      expect(await store.shoes.defaultId(), isNull);
      await store.shoes.setRetired(a, true);
      expect((await store.shoes.watchAll().first).map((s) => s.name), ['C shoe', 'A shoe', 'B shoe']);
      await store.shoes.setRetired(a, false);
      expect((await store.shoes.watchAll().first).map((s) => s.id), [a, c, b]);
      expect((await store.shoes.watchAll().first).first.retiredAt, isNull);
    });

    test('shoe edits are dirty for sync', () async {
      final a = await store.shoes.add('Pegasus');
      await db.customStatement('update shoes set dirty = 0');
      await store.shoes.setDefault(a);
      expect((await db.select(db.shoes).getSingle()).dirty, 1);
    });
  });

  group('the default shoe', () {
    Recording rec(String ext, {String type = 'run'}) => Recording(source: 'file', type: type, start: DateTime.utc(2026, 11, 1, 7), elapsedSec: 1800, externalId: ext, distanceKm: 5);

    test('goes on a new ingested or saved Run, not on an existing one or a Run once there is none', () async {
      final none = (await store.ingest(rec('before'))).id!;
      expect((await store.watch(none).first).shoeId, isNull);
      final a = await store.shoes.add('Pegasus');
      await store.shoes.setDefault(a);
      final ingested = (await store.ingest(Recording(source: 'file', type: 'run', start: DateTime.utc(2026, 11, 3, 7), elapsedSec: 1800, externalId: 'x', distanceKm: 5))).id!;
      expect((await store.watch(ingested).first).shoeId, a);
      final saved = await store.save(type: 'interval', startedAt: DateTime(2026, 11, 5), distanceKm: 3, durationSec: 900);
      expect((await store.watch(saved).first).shoeId, a);
      expect((await store.watch(none).first).shoeId, isNull); // earlier Runs are left alone
      await store.shoes.setDefault(await store.shoes.add('Ghost'));
      await store.save(id: saved, type: 'interval', startedAt: DateTime(2026, 11, 5), distanceKm: 4, durationSec: 900); // editing a Run keeps its shoe
      expect((await store.watch(saved).first).shoeId, a);
    });

    test('a retired default is not applied', () async {
      final a = await store.shoes.add('Pegasus');
      await store.shoes.setDefault(a);
      await store.shoes.setRetired(a, true);
      final id = (await store.ingest(rec('y'))).id!;
      expect((await store.watch(id).first).shoeId, isNull);
    });

    test('a later import merging into a Run keeps its shoe', () async {
      final a = await store.shoes.add('Pegasus');
      await store.shoes.setDefault(a);
      final id = (await store.ingest(rec('z'))).id!;
      await store.shoes.setDefault(await store.shoes.add('Ghost'));
      await store.ingest(Recording(source: 'health_connect', type: 'run', start: DateTime.utc(2026, 11, 1, 7), elapsedSec: 1800, externalId: 'hc', avgHr: 150));
      expect((await store.watch(id).first).shoeId, a);
    });
  });

  group('heatmap routes', () {
    test('uses stored routes of live outdoor Runs with at least two points', () async {
      await run('a', route: '32.00000,34.80000;32.00100,34.80100;32.00200,34.80200');
      await run('b', route: '32.1,34.8'); // one point
      await run('c', route: null);
      await run('d', type: 'interval', route: '32.0,34.8;32.1,34.9');
      await run('e', route: '32.0,34.8;32.1,34.9', deleted: DateTime(2026, 11, 2));
      await run('f', type: 'treadmill', route: '32.0,34.8;32.1,34.9'); // an old treadmill row: not a Run
      final routes = heatmapRoutes(await store.watchAll().first);
      expect(routes, unorderedEquals([
        [(32.0, 34.8), (32.001, 34.801), (32.002, 34.802)],
        [(32.0, 34.8), (32.1, 34.9)], // the Interval run counts
      ]));
    });

    test('hundreds of Runs turn into routes quickly', () async {
      final route = [for (var i = 0; i < 200; i++) '${32 + i * 0.0001},${34.8 + i * 0.0001}'].join(';');
      final runs = [
        for (var i = 0; i < 600; i++)
          CardioData(id: 'r$i', type: 'run', startedAt: DateTime(2026, 1, 1).add(Duration(days: i)), durationSec: 1500, route: route, editedFields: const [], createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0),
      ];
      final sw = Stopwatch()..start();
      final routes = heatmapRoutes(runs);
      expect(routes, hasLength(600));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}
