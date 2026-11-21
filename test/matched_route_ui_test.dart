import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';
import 'package:timburr/ui/running/race_predictor.dart';

Track loopTrack(double lat0) => Track(
      time: [for (var i = 0; i < 300; i++) i * 6],
      distance: [for (var i = 0; i < 300; i++) i * 10.5],
      lat: [for (var i = 0; i < 300; i++) lat0 + 0.0045 * sin(2 * pi * i / 299)],
      lon: [for (var i = 0; i < 300; i++) 34.8 + 0.0053 * cos(2 * pi * i / 299)],
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1)); // drift closes its stream with a zero timer
  }

  testWidgets('the Run page link names the group and opens the trend page; a lone Run has no link', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CardioStore(db);
    Future<String> add(String ext, DateTime at, double lat) async =>
        (await store.ingest(Recording(source: 'file', type: 'run', start: at, elapsedSec: 1800, externalId: ext, distanceKm: 3.1, track: loopTrack(lat)))).id!;
    final ids = await tester.runAsync(() async => [
          await add('a', DateTime(2026, 11, 1, 7), 32.0),
          await add('b', DateTime(2026, 11, 8, 7), 32.0),
          await add('c', DateTime(2026, 11, 9, 7), 33.0),
        ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [MatchedRouteTile(store: store, runId: ids![0]), MatchedRouteTile(store: store, runId: ids[2])]))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Run on this route 2 times'), findsOneWidget); // only for a and not the lone c
    await tester.tap(find.text('Run on this route 2 times'));
    await tester.pumpAndSettle();
    expect(find.text('Same route'), findsOneWidget);
    expect(find.text('2 Runs'), findsOneWidget);
    await close(tester);
  });
}
