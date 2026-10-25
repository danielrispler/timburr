import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

/// Columns every synced table shares with supabase/migrations/001_init.sql, plus local `dirty`.
mixin Synced on Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()(); // filled by the server default on first push
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get dirty => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Postgres text[] stored as a JSON array.
class StringList extends TypeConverter<List<String>, String> {
  const StringList();
  @override
  List<String> fromSql(String fromDb) => (jsonDecode(fromDb) as List).cast<String>();
  @override
  String toSql(List<String> value) => jsonEncode(value);
}

class Exercises extends Table with Synced {
  TextColumn get libraryId => text().nullable().unique()();
  TextColumn get name => text().nullable()();
  TextColumn get loadType => text().nullable()();
  TextColumn get muscles => text().map(const StringList()).withDefault(const Constant('[]'))();
  TextColumn get equipment => text().nullable()();
  TextColumn get stickyNote => text().nullable()();
  IntColumn get lastRestSec => integer().nullable()();
}

class Routines extends Table with Synced {
  TextColumn get name => text()();
  TextColumn get stickyNote => text().nullable()();
}

class RoutineExercises extends Table with Synced {
  TextColumn get routineId => text().references(Routines, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  TextColumn get backupExerciseId => text().nullable().references(Exercises, #id)();
  IntColumn get position => integer()();
}

/// Planned sets of a routine exercise; starting the routine copies them into `sets`.
@DataClassName('RoutineSet')
class RoutineSets extends Table with Synced {
  TextColumn get routineExerciseId => text().references(RoutineExercises, #id)();
  IntColumn get setNumber => integer()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get durationSec => integer().nullable()();
}

class Workouts extends Table with Synced {
  TextColumn get routineId => text().nullable().references(Routines, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  // Google Health stats, typed in from a screenshot.
  IntColumn get avgHr => integer().nullable()();
  IntColumn get calories => integer().nullable()();
  IntColumn get activeSec => integer().nullable()();
  IntColumn get effort => integer().nullable()();
  IntColumn get cardioLoad => integer().nullable()();
}

class WorkoutExercises extends Table with Synced {
  TextColumn get workoutId => text().references(Workouts, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  TextColumn get backupExerciseId => text().nullable().references(Exercises, #id)(); // swap exchanges the two
  IntColumn get position => integer()();
  TextColumn get notes => text().nullable()();
  BoolColumn get supersetWithNext => boolean().withDefault(const Constant(false))();
}

@DataClassName('WorkoutSet')
class WorkoutSets extends Table with Synced {
  @override
  String get tableName => 'sets';

  TextColumn get workoutExerciseId => text().references(WorkoutExercises, #id)();
  IntColumn get setNumber => integer()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get durationSec => integer().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  BoolColumn get isDrop => boolean().withDefault(const Constant(false))(); // a drop set of the set before it
}

class Cardio extends Table with Synced {
  TextColumn get type => text()();
  DateTimeColumn get startedAt => dateTime()();
  RealColumn get distanceKm => real().nullable()(); // null for sports
  IntColumn get durationSec => integer()();
  IntColumn get avgHr => integer().nullable()();
  RealColumn get inclinePct => real().nullable()();
  IntColumn get rpe => integer().nullable()();
  TextColumn get notes => text().nullable()();
}

/// Local only: last pulled `server_updated_at` per synced table.
class SyncCursors extends Table {
  TextColumn get syncedTable => text()();
  DateTimeColumn get cursor => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {syncedTable};
}

@DriftDatabase(tables: [Exercises, Routines, RoutineExercises, RoutineSets, Workouts, WorkoutExercises, WorkoutSets, Cardio, SyncCursors])
class AppDb extends _$AppDb {
  AppDb([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'timburr'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(routineSets);
            await m.alterTable(TableMigration(cardio)); // distance_km becomes nullable
          }
          if (from < 3) {
            await m.addColumn(workoutSets, workoutSets.isDrop);
            await m.addColumn(routineExercises, routineExercises.backupExerciseId);
            await m.addColumn(workoutExercises, workoutExercises.backupExerciseId);
            for (final c in [workouts.avgHr, workouts.calories, workouts.activeSec, workouts.effort, workouts.cardioLoad]) {
              await m.addColumn(workouts, c);
            }
          }
        },
        beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
      );

  /// Synced tables in dependency order, parents first.
  List<TableInfo> get syncedTables => [exercises, routines, routineExercises, routineSets, workouts, workoutExercises, workoutSets, cardio];

  /// The one local write path: upserts [row] (SQL column name to value), stamping `updated_at` and `dirty = 1`.
  /// On conflict only the columns in [row] are updated; omitted columns keep their stored values.
  Future<void> save<D>(TableInfo<Table, D> table, Map<String, Object?> row) {
    final values = {...row, 'updated_at': DateTime.now(), 'dirty': 1};
    return into(table).insertOnConflictUpdate(RawValuesInsertable<D>({
      for (final MapEntry(:key, :value) in values.entries)
        key: Variable(value is List ? jsonEncode(value) : value),
    }));
  }
}
