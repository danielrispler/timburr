import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/running.dart';
import 'package:timburr/data/track.dart';
import 'package:timburr/ui/running/fitness_section.dart';

class _CountingStore extends CardioStore {
  _CountingStore(super.db);
  int trackWatches = 0;

  @override
  Stream<Map<String, Track>> watchHrTracks() {
    trackWatches++;
    return super.watchHrTracks();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets("the chart shows today's Fitness, Fatigue and Form", (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CardioStore(db);
    // One 42-minute Run without HR today: estimated at zone 2 = 84 load, Fitness 84/42 = 2, Fatigue 84/7 = 12, Form -10.
    final now = DateTime(2026, 11, 21, 12);
    await tester.runAsync(() => store.save(type: 'run', startedAt: DateTime(2026, 11, 21, 7), distanceKm: 6, durationSec: 42 * 60));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [FitnessSection(store: store, runs: store.watchAll().map(runsOf), now: now)]))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Fitness & Freshness'), findsOneWidget);
    String today(String label) => tester.widget<Text>(find.byKey(ValueKey('today $label'))).data!;
    expect((today('Fitness'), today('Fatigue'), today('Form')), ('2', '12', '-10'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a rebuild does not resubscribe to the HR tracks', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = _CountingStore(db);
    final runs = store.watchAll().map(runsOf);
    final now = DateTime(2026, 11, 21, 12);
    Widget app(bool toggle) => MaterialApp(home: Scaffold(body: ListView(children: [Text('$toggle'), FitnessSection(store: store, runs: runs, now: now)])));
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(store.trackWatches, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
