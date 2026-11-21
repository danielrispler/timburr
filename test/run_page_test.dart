import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';
import 'package:timburr/ui/cardio/run_page.dart';

Track track({bool gps = true, bool hr = true}) => Track(
      time: [for (var i = 0; i < 700; i++) i],
      distance: [for (var i = 0; i < 700; i++) i * 3.0],
      lat: gps ? [for (var i = 0; i < 700; i++) 32.0 + i * 0.00003] : null,
      lon: gps ? [for (var i = 0; i < 700; i++) 34.8] : null,
      hr: hr ? [for (var i = 0; i < 700; i++) 150] : null,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_map caches tiles in the app cache directory.
  final cache = Directory.systemTemp.createTempSync('tiles');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => cache.path);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1)); // drift closes its stream with a zero timer
  }

  Future<void> show(WidgetTester tester, {required bool gps, bool hr = true}) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CardioStore(db);
    final id = await tester.runAsync(() async => (await store.ingest(Recording(source: 'file', type: 'run', start: DateTime(2026, 11, 10, 7), elapsedSec: 699, externalId: 'a', distanceKm: 2.1, track: track(gps: gps, hr: hr)))).id!);
    await tester.pumpWidget(MaterialApp(home: RunPage(store: store, id: id!)));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a Run with a route shows the map, its credit, stats and splits', (tester) async {
    await show(tester, gps: true);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('© OpenStreetMap'), findsOneWidget);
    expect(find.text('Morning run'), findsOneWidget);
    expect(find.text('Moving time'), findsOneWidget);
    expect(find.text('km 1'), findsOneWidget);
    expect(find.text('Heart rate'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a Run without a route has the same page and no map', (tester) async {
    await show(tester, gps: false);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Moving time'), findsOneWidget);
    expect(find.text('km 1'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a Run with heart rate shows the zone bar, a Run without hides it', (tester) async {
    await show(tester, gps: true); // 150 bpm of the default Max HR 190 is zone 4
    expect(find.text('Heart rate zones'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await close(tester);
    await show(tester, gps: true, hr: false);
    expect(find.text('Heart rate zones'), findsNothing);
    await close(tester);
  });

  testWidgets('openRun from a tab keeps the bottom bar', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CardioStore(db);
    final id = await tester.runAsync(() async => (await store.ingest(Recording(source: 'file', type: 'run', start: DateTime(2026, 11, 10, 7), elapsedSec: 699, externalId: 'a', distanceKm: 2.1, track: track(gps: false)))).id!);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: const Text('bottom bar'),
        body: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (context) => TextButton(onPressed: () => openRun(context, store, id!), child: const Text('open')))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Moving time'), findsOneWidget);
    expect(find.text('bottom bar'), findsOneWidget);
    await close(tester);
  });
}
