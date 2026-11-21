import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/ui/cardio/cardio_form.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the end time sets Elapsed time (end minus start) and marks only that edited', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CardioStore(db);
    final id = (await tester.runAsync(() async => (await store.ingest(Recording(source: 'file', type: 'run', start: DateTime(2026, 11, 10, 7), elapsedSec: 699, movingSec: 600, externalId: 'a', distanceKm: 2.1))).id!))!;
    final run = (await tester.runAsync(() => store.watch(id).first))!;
    await tester.pumpWidget(MaterialApp(home: CardioForm(store: store, existing: run)));

    expect(find.textContaining('Ends 7:11'), findsOneWidget); // 07:00:00 + 11:39
    expect(find.text('Elapsed 11:39'), findsOneWidget);

    await tester.tap(find.textContaining('Ends'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '7');
    await tester.enterText(fields.at(1), '30');
    await tester.tap(find.text('AM'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Elapsed 30:00'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    final saved = (await tester.runAsync(() => store.watch(id).first))!;
    expect((saved.elapsedSec, saved.durationSec, saved.startedAt), (1800, 600, run.startedAt));
    expect(saved.editedFields, ['elapsed_sec']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
