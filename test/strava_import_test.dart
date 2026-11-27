import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/run_file.dart';
import 'package:timburr/data/strava_import.dart';
import 'package:timburr/data/strava_tcx.dart';

import 'strava_tcx_test.dart' show points, tcx;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late CardioStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
  });
  tearDown(() => db.close());

  // One file per day, so none overlap.
  List<ParsedFile> files() => [
        parseStravaTcx('2026-11-01T20_00_00+02_00_PT8M48S_ריצה.tcx', tcx([points(60, day: 1)], id: 'map')),
        parseStravaTcx('2026-11-02T20_00_00+02_00_PT8M48S_ריצה.tcx', tcx([points(30, day: 2)], id: 'sparse')),
        parseStravaTcx('2026-11-03T20_00_00+02_00_PT8M48S_ריצה על הליכון.tcx', tcx([points(60, gps: false, day: 3)], id: 'tread')),
        parseStravaTcx('2026-11-04T20_00_00+02_00_PT3S_ריצה.tcx', tcx([[for (var i = 0; i < 3; i++) (DateTime.utc(2026, 11, 4, 18, i).toIso8601String(), 0.0, null, null)]], id: 'zero')),
      ];

  test('the preview counts new Runs, maps, routeless and skipped files (a treadmill file is skipped), and saves nothing', () async {
    final p = await previewStrava(store, files());
    expect((p.newRuns, p.withMap, p.noRoute, p.skipped), (2, 1, 1, 2));
    expect((p.merged, p.alreadyImported), (0, 0));
    expect(await store.watchAll().first, isEmpty);
  });

  test('saving creates the Runs, and importing the same files again changes nothing', () async {
    expect(await importStrava(store, files()), (created: 2, merged: 0));
    expect(await store.watchAll().first, hasLength(2));
    final again = await previewStrava(store, files());
    expect((again.newRuns, again.alreadyImported), (0, 2));
    expect(await importStrava(store, files()), (created: 0, merged: 0));
    expect(await store.watchAll().first, hasLength(2));
  });

  test('the preview of two overlapping files in one pick matches what Save does', () async {
    List<ParsedFile> pick() => [
          parseStravaTcx('2026-11-01T20_00_00+02_00_PT1M_ריצה.tcx', tcx([points(60, day: 1)], id: 'a')),
          parseStravaTcx('2026-11-01T20_00_30+02_00_PT1M_ריצה.tcx', tcx([points(60, day: 1, t0: 30)], id: 'b')),
          parseStravaTcx('2026-11-01T20_00_00+02_00_PT1M_ריצה.tcx', tcx([points(60, day: 1)], id: 'a')),
        ];
    final p = await previewStrava(store, pick());
    expect((p.newRuns, p.merged, p.alreadyImported), (1, 1, 1));
    expect(await importStrava(store, pick()), (created: 1, merged: 1));
    expect(await store.watchAll().first, hasLength(1));
  });

  test('a file that overlaps a Run already there is a merge, not a new Run', () async {
    await store.save(type: 'run', startedAt: DateTime.utc(2026, 11, 1, 18), distanceKm: 0.2, durationSec: 60);
    final p = await previewStrava(store, files());
    expect((p.newRuns, p.merged), (1, 1));
  });
}
