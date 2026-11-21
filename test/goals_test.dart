import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/goals.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/ui/running/goals_section.dart';

CardioData run(DateTime at, double km) => CardioData(
    id: '$at', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0, editedFields: const [],
    type: 'run', startedAt: at, distanceKm: km, durationSec: 1500);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  // Saturday 21 Nov 2026; its week starts Monday 16 Nov.
  final now = DateTime(2026, 11, 21, 9);
  final runs = [
    run(DateTime(2026, 11, 17, 7), 6), // this week
    run(DateTime(2026, 11, 9, 7), 10), // last week
    run(DateTime(2026, 1, 3, 7), 84), // this year
    run(DateTime(2025, 12, 31, 7), 500), // last year
  ];

  test('weekly progress counts Runs since Monday', () {
    final p = weeklyProgress(runs, 30, now);
    expect((p.doneKm, p.goalKm, p.fraction, p.remainingKm), (6.0, 30.0, 0.2, 24.0));
  });

  test('yearly progress counts Runs since 1 January', () {
    final p = yearlyProgress(runs, 400, now);
    expect((p.doneKm, p.remainingKm, p.fraction), (100.0, 300.0, 0.25));
  });

  test('a reached goal has nothing remaining and a fraction of at least 1', () {
    final p = yearlyProgress(runs, 50, now);
    expect((p.remainingKm, p.fraction), (0.0, 2.0));
    expect(weeklyPaceNeeded(p, now), 0);
  });

  test('weekly pace needed is the remaining km over the weeks left in the year', () {
    final p = yearlyProgress(runs, 400, now); // 300 km left
    final weeksLeft = DateTime(2027).difference(now).inMinutes / (7 * 24 * 60); // 40 days and 15 hours
    expect(weeklyPaceNeeded(p, now), closeTo(300 / weeksLeft, 1e-9));
    expect(weeksLeft, closeTo(5.80, 0.01));
  });

  test('weekly pace on the last minute of the year is finite', () {
    final end = DateTime(2026, 12, 31, 23, 59);
    expect(weeklyPaceNeeded(yearlyProgress(runs, 400, end), end).isFinite, isTrue);
  });

  test('the store keeps one row, clears a goal with null, revives after a delete, and rejects zero', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final goals = GoalStore(db);
    expect(await goals.watch().first, isNull);
    await goals.set(weeklyKm: 30, yearlyKm: 1500);
    await goals.set(weeklyKm: 25);
    final g = (await goals.watch().first)!;
    expect((g.weeklyKm, g.yearlyKm, g.dirty), (25.0, null, 1));
    expect(await db.select(db.goals).get(), hasLength(1));
    await db.save(db.goals, {'id': g.id, 'deleted_at': DateTime.utc(2026, 11, 1)});
    expect(await goals.watch().first, isNull);
    await goals.set(yearlyKm: 1000);
    final revived = (await goals.watch().first)!;
    expect((revived.weeklyKm, revived.yearlyKm), (null, 1000.0));
    expect(() => goals.set(weeklyKm: 0), throwsArgumentError);
  });

  testWidgets('Progress shows both rings and the pace needed, and the dialog saves goals', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final cardio = CardioStore(db);
    await tester.runAsync(() async {
      await cardio.ingest(Recording(source: 'manual', type: 'run', start: DateTime(2026, 11, 17, 7), elapsedSec: 1800, distanceKm: 6));
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GoalsSection(store: cardio, runs: cardio.watchAll(), now: now)))));
    Future<void> settle() async {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();
    }

    await settle();
    expect(find.text('Set a weekly or yearly goal'), findsOneWidget);

    await tester.tap(find.text('Set a weekly or yearly goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('weekly-goal')), '30');
    await tester.enterText(find.byKey(const ValueKey('yearly-goal')), '400');
    await tester.tap(find.text('Save'));
    await settle();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('weekly-ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('yearly-ring')), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('6.0 / 30 km'), findsOneWidget);
    expect(find.textContaining('km a week to reach it'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
