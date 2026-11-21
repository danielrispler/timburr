import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/running.dart';
import 'package:timburr/ui/running/heatmap_screen.dart';
import 'package:timburr/ui/running/shoes_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = Directory.systemTemp.createTempSync('tiles');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => cache.path);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1)); // drift closes its stream with a zero timer
  }

  late AppDb db;
  late CardioStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
  });
  tearDown(() => db.close());

  String routeAt(int i) => [for (var p = 0; p < 200; p++) '${32 + i * 0.001 + p * 0.0001},${34.8 + p * 0.0001}'].join(';');

  testWidgets('the heatmap draws 400 Runs as one polyline layer, and says so when there are none', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 400; i++) {
        await db.save(db.cardio, {'id': 'r$i', 'type': 'run', 'started_at': DateTime(2026, 1, 1).add(Duration(days: i)), 'distance_km': 5.0, 'duration_sec': 1500, 'route': routeAt(i)});
      }
    });
    final sw = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(home: HeatmapScreen(runs: store.watchAll().map(runsOf))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines, hasLength(400));
    expect(find.text('OpenStreetMap'), findsOneWidget);
    expect(sw.elapsedMilliseconds, lessThan(5000));
    await close(tester);

    await tester.pumpWidget(MaterialApp(home: HeatmapScreen(runs: Stream.value(const <CardioData>[]))));
    await tester.pump();
    expect(find.textContaining('No routes yet'), findsOneWidget);
    await close(tester);
  });

  testWidgets('adding shoes from the screen', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final runs = store.watchAll().map(runsOf);
    await tester.pumpWidget(MaterialApp(home: ShoesScreen(store: store, runs: runs)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Add a pair'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'Pegasus');
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pegasus'), findsOneWidget);
    expect(find.text('0.0 km'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a shoe shows its total, and retiring it keeps the total', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final shoe = await store.shoes.add('Pegasus');
      await db.save(db.cardio, {'id': 'r1', 'type': 'run', 'started_at': DateTime(2026, 11, 1), 'distance_km': 6.0, 'duration_sec': 1800, 'shoe_id': shoe});
    });
    await tester.pumpWidget(MaterialApp(home: ShoesScreen(store: store, runs: store.watchAll().map(runsOf))));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('6.0 km'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retire'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('6.0 km · Retired'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the Run page picker assigns and clears a pair, and hides until a pair exists', (tester) async {
    final id = (await tester.runAsync(() => store.save(type: 'run', startedAt: DateTime(2026, 11, 1), distanceKm: 6, durationSec: 1800)))!;
    Widget page() => MaterialApp(home: Scaffold(body: StreamBuilder<CardioData>(stream: store.watch(id), builder: (_, s) => s.data == null ? const SizedBox() : ShoePicker(store: store, run: s.data!))));
    await tester.pumpWidget(page());
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Shoes'), findsNothing);

    await tester.runAsync(() => store.shoes.add('Pegasus'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('None'), findsOneWidget);
    await tester.tap(find.text('Shoes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pegasus'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => store.watch(id).first))!.shoeId, isNotNull);
    expect(find.text('Pegasus'), findsOneWidget);

    await tester.tap(find.text('Shoes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No shoes'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => store.watch(id).first))!.shoeId, isNull);
    await close(tester);
  });
}
