import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/routines.dart';
import 'package:timburr/data/workouts.dart';
import 'package:timburr/ui/stats/stats_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('one shared stats stream per app; a rename shows without a restart', () async {
    final db = AppDb(NativeDatabase.memory());
    final catalog = Catalog(db, () async => '[]');
    final stores = (routines: RoutineStore(db), workouts: WorkoutStore(db), cardio: CardioStore(db), catalog: catalog);
    final id = await catalog.saveCustom(name: 'Press', loadType: 'weighted');
    final w = await stores.workouts.start();
    await stores.workouts.addExercise(w, (await catalog.byId(id))!);
    await stores.workouts.addSet((await db.select(db.workoutExercises).getSingle()).id);
    await stores.workouts.finish(w);

    expect(identical(watchStats(stores), watchStats(stores)), isTrue);
    final names = watchStats(stores).map((d) => d.exercises[id]?.name).where((n) => n != null);
    expect(await names.first, 'Press');
    // A late listener gets the latest value at once.
    expect(await names.first, 'Press');
    final next = names.firstWhere((n) => n == 'Bench');
    await catalog.saveCustom(id: id, name: 'Bench', loadType: 'timed');
    expect(await next, 'Bench');
    await db.close();
  });
}
