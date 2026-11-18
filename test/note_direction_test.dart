import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/workouts.dart';
import 'package:timburr/ui/workouts/exercise_notes.dart';

const _library = [
  {
    'id': 'Barbell_Squat', 'name': 'Barbell Squat', 'category': 'strength', 'equipment': 'barbell',
    'primaryMuscles': ['quadriceps'], 'secondaryMuscles': [], 'instructions': [],
  },
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a Hebrew note on an exercise card is right to left, so it aligns right', (tester) async {
    const note = 'לכל רגל ומשקולת בכל יד';
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final catalog = Catalog(db, () async => jsonEncode(_library));
    final store = WorkoutStore(db);
    late WorkoutExercise item;
    await tester.runAsync(() async {
      final id = await store.start();
      await store.addExercise(id, (await catalog.list(query: 'squat')).single);
      item = (await store.watchExercises(id).first).single;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExerciseNotes(store: store, catalog: catalog, item: item, stickyNote: note, isLast: true),
      ),
    ));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(note));
    expect(paragraph.textDirection, TextDirection.rtl);
  });
}
