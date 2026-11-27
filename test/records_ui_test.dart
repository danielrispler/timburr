import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/routines.dart';
import 'package:timburr/data/track.dart';
import 'package:timburr/data/workouts.dart';
import 'package:timburr/ui/cardio/run_efforts.dart';
import 'package:timburr/ui/running/running_records.dart';

/// 1.2 km at [speed] m/s, a point a second.
Track track(double speed) => Track(time: [for (var i = 0; i <= 400; i++) i], distance: [for (var i = 0; i <= 400; i++) i * speed]);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1)); // drift closes its stream with a zero timer
  }

  Future<(CardioStore, String, String)> seed(WidgetTester tester, AppDb db) async {
    final store = CardioStore(db);
    return (await tester.runAsync(() async {
      Future<String> add(String id, int day, double speed, {String type = 'run'}) async =>
          (await store.ingest(Recording(source: 'file', type: type, start: DateTime(2026, 11, day, 7), elapsedSec: 400, externalId: id, distanceKm: 0.4 * speed, track: track(speed)))).id!;
      final slow = await add('slow', 1, 3);
      final fast = await add('fast', 2, 4);
      await add('tm', 3, 6, type: 'treadmill'); // an old treadmill row: faster than both, but no longer a Run
      return (store, slow, fast);
    }))!;
  }

  testWidgets('the Run page shows its efforts, with the PR badge only on the fastest ever', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final (store, slow, fast) = await seed(tester, db);
    Future<void> show(String id) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RunBestEfforts(store: store, runId: id)))));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    await show(fast);
    expect(find.text('1 km'), findsOneWidget);
    expect(find.text('4:10'), findsOneWidget);
    expect(find.byType(PrBadge), findsNWidgets(2)); // 400 m and 1 km
    await show(slow);
    expect(find.text('5:33'), findsOneWidget);
    expect(find.byType(PrBadge), findsNothing);
    await close(tester);
  });

  testWidgets('Records lists each PR and the longest Run, and the top efforts per distance', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final (store, _, _) = await seed(tester, db);
    final stores = (routines: RoutineStore(db), workouts: WorkoutStore(db), cardio: store, catalog: Catalog(db));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RunningRecords(stores: stores, runs: store.watchAll()))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Personal records'), findsOneWidget);
    expect(find.text('Longest Run'), findsOneWidget);
    expect(find.text('1.6 km'), findsOneWidget); // the fast Run; the old treadmill row (2.4 km) is not a Run
    expect(find.text('Top 1 km'), findsOneWidget);
    expect(find.text('1. 4:10'), findsOneWidget);
    expect(find.text('2. 5:33'), findsOneWidget);
    await close(tester);
  });
}
