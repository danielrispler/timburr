import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  setUp(() => db = AppDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('save stamps updated_at and dirty on insert and on update', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    await db.save(db.exercises, {'id': 'a', 'name': 'Curl', 'load_type': 'weighted', 'muscles': ['biceps']});
    var row = await db.select(db.exercises).getSingle();
    expect(row.dirty, 1);
    expect(row.updatedAt.isAfter(before), isTrue);
    expect(row.muscles, ['biceps']);

    await db.customStatement("update exercises set dirty = 0, updated_at = '2000-01-01T00:00:00.000'");
    await db.save(db.exercises, {'id': 'a', 'sticky_note': 'slow'});
    row = await db.select(db.exercises).getSingle();
    expect(row.dirty, 1);
    expect(row.updatedAt.year, greaterThan(2000));
    expect(row.name, 'Curl');
    expect(row.stickyNote, 'slow');
  });

  test('foreign keys are enforced', () async {
    final orphan = db.save(db.routineExercises, {'id': 'x', 'routine_id': 'nope', 'exercise_id': 'nope', 'position': 0});
    await expectLater(orphan, throwsA(anything));
  });
}
