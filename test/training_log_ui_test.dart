import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/routines.dart';
import 'package:timburr/data/workouts.dart';
import 'package:timburr/ui/cardio/run_page.dart';
import 'package:timburr/ui/running/training_log.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  // Saturday 21 Nov 2026.
  final now = DateTime(2026, 11, 21, 9);

  testWidgets('the calendar shows the month Runs and totals, the streak, and a day opens its Run', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final cardio = CardioStore(db);
    final stores = (routines: RoutineStore(db), workouts: WorkoutStore(db), cardio: cardio, catalog: Catalog(db));
    await tester.runAsync(() async {
      await cardio.ingest(Recording(source: 'manual', type: 'run', start: DateTime(2026, 11, 18, 7), elapsedSec: 1800, distanceKm: 5));
      await cardio.ingest(Recording(source: 'manual', type: 'run', start: DateTime(2026, 11, 10, 7), elapsedSec: 1800, distanceKm: 3));
      await cardio.ingest(Recording(source: 'manual', type: 'run', start: DateTime(2026, 10, 5, 7), elapsedSec: 1800, distanceKm: 9));
      final w = await stores.workouts.start(at: DateTime(2026, 11, 12, 18), done: true);
      expect(w, isNotEmpty);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TrainingLog(stores: stores, runs: cardio.watchAll(), now: now)))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump();

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('8.0 km'), findsOneWidget); // 5 + 3, not October's 9
    expect(find.text('2 weeks running streak'), findsOneWidget);

    // A calendar day with one Run opens it.
    await tester.tap(find.byKey(const ValueKey('day-18')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RunPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(RunPage))).pop();
    await tester.pumpAndSettle();

    // Swiping right goes to the month before.
    await tester.drag(find.byKey(const ValueKey('day-10')), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('9.0 km'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
