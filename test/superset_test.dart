import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/workouts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late WorkoutStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = WorkoutStore(db);
  });
  tearDown(() => db.close());

  Future<List<WorkoutExercise>> items(String w) => store.watchExercises(w).first;
  Future<List<List<String>>> groups(String w) async =>
      [for (final g in supersetGroups(await items(w))) [for (final e in g) e.exerciseId]];
  Future<void> link(String w, int i) async =>
      store.saveExercise((await items(w))[i].copyWith(supersetWithNext: true));
  final a = libraryRowId('A'), b = libraryRowId('B'), c = libraryRowId('C'), d = libraryRowId('D');

  Future<String> workout() async {
    final w = await store.start();
    for (final id in ['A', 'B', 'C', 'D']) {
      await store.addExercise(w, CatalogEntry(name: id, libraryId: id, loadType: 'weighted'));
    }
    return w;
  }

  test('no links: every card is its own group', () async {
    expect(await groups(await workout()), [[a], [b], [c], [d]]);
  });

  test('links chain consecutive cards; a link on the last card is ignored', () async {
    final w = await workout();
    await link(w, 0);
    await link(w, 1);
    await link(w, 3);
    expect(await groups(w), [[a, b, c], [d]]);
  });

  test('grouping follows the order after a reorder', () async {
    final w = await workout();
    await link(w, 0); // A+B
    await store.move((await items(w))[0].id, 1); // B, A(linked), C, D
    expect(await groups(w), [[b], [a, c], [d]]);
  });

  test('removing a card regroups the rest', () async {
    final w = await workout();
    await link(w, 0); // A+B
    await link(w, 1); // B+C
    await store.remove((await items(w))[1].id);
    expect(await groups(w), [[a], [c], [d]]); // the link into B does not join A to C
    await store.remove((await items(w))[1].id);
    expect(await groups(w), [[a], [d]]);
  });

  test('session and workout notes survive reopening; sticky notes carry to the next workout', () async {
    final w = await workout();
    await store.setNotes(w, 'felt good');
    final first = (await items(w)).first;
    await store.saveExercise(first.copyWith(notes: const Value('grip wider')));
    await Catalog(db, () async => '[]').setStickyNote(first.exerciseId, 'seat 4');

    final reopened = WorkoutStore(db);
    expect((await reopened.watchWorkout(w).first).notes, 'felt good');
    expect((await reopened.watchExercises(w).first).first.notes, 'grip wider');

    final next = await reopened.start();
    await reopened.addExercise(next, CatalogEntry(name: 'A', libraryId: 'A', loadType: 'weighted'));
    final again = (await reopened.watchExercises(next).first).single;
    expect(again.notes, isNull);
    expect((await Catalog(db, () async => '[]').byId(again.exerciseId))!.stickyNote, 'seat 4');
  });

  group('superset rows', () {
    var n = 0;
    WorkoutSet set(String we, {bool drop = false}) => WorkoutSet(
        id: 's${n++}', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0,
        workoutExerciseId: we, setNumber: 1, done: false, isDrop: drop);

    test('rows alternate by round; drops stay under their set; uneven counts trail', () {
      final a1 = set('a'), a1d = set('a', drop: true), a2 = set('a'), a3 = set('a'), b1 = set('b'), b2 = set('b');
      final rows = supersetRows([[a1, a1d, a2, a3], [b1, b2]]);
      expect([for (final r in rows) r.set.id], [a1.id, a1d.id, b1.id, a2.id, b2.id, a3.id]);
      expect([for (final r in rows) r.exercise], [0, 0, 1, 0, 1, 0]);
      // Rest is offered only after the last row of a round.
      expect([for (final r in rows) r.endsRound], [false, false, true, false, true, true]);
    });

    test('a single card: every set and its drops end a round', () {
      final x = set('a'), xd = set('a', drop: true), y = set('a');
      expect([for (final r in supersetRows([[x, xd, y]])) r.endsRound], [false, true, true]);
    });
  });
}
