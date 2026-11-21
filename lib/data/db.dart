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

@TableIndex(name: 'exercises_dirty', columns: {#dirty})
class Exercises extends Table with Synced {
  TextColumn get libraryId => text().nullable().unique()();
  TextColumn get name => text().nullable()();
  TextColumn get loadType => text().nullable()();
  TextColumn get muscles => text().map(const StringList()).withDefault(const Constant('[]'))();
  TextColumn get equipment => text().nullable()();
  TextColumn get stickyNote => text().nullable()();
  IntColumn get lastRestSec => integer().nullable()();
}

@TableIndex(name: 'routines_dirty', columns: {#dirty})
class Routines extends Table with Synced {
  TextColumn get name => text()();
  TextColumn get stickyNote => text().nullable()();
}

@TableIndex(name: 'routine_exercises_dirty', columns: {#dirty})
class RoutineExercises extends Table with Synced {
  TextColumn get routineId => text().references(Routines, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  TextColumn get backupExerciseId => text().nullable().references(Exercises, #id)(); // retired in v6 for alternativeIds
  TextColumn get alternativeIds => text().map(const StringList()).withDefault(const Constant('[]'))(); // the slot's other exercises
  IntColumn get position => integer()();
}

/// Planned sets of a routine exercise; starting the routine copies them into `sets`.
@TableIndex(name: 'routine_sets_dirty', columns: {#dirty})
@DataClassName('RoutineSet')
class RoutineSets extends Table with Synced {
  TextColumn get routineExerciseId => text().references(RoutineExercises, #id)();
  IntColumn get setNumber => integer()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get durationSec => integer().nullable()();
}

@TableIndex(name: 'workouts_dirty', columns: {#dirty})
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

@TableIndex(name: 'workout_exercises_dirty', columns: {#dirty})
class WorkoutExercises extends Table with Synced {
  TextColumn get workoutId => text().references(Workouts, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  TextColumn get backupExerciseId => text().nullable().references(Exercises, #id)(); // retired in v6 for alternativeIds
  TextColumn get alternativeIds => text().map(const StringList()).withDefault(const Constant('[]'))(); // swap trades one for exerciseId
  IntColumn get position => integer()();
  TextColumn get notes => text().nullable()();
  BoolColumn get supersetWithNext => boolean().withDefault(const Constant(false))();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))(); // not done today; its sets count nowhere
}

@TableIndex(name: 'sets_dirty', columns: {#dirty})
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

@TableIndex(name: 'cardio_dirty', columns: {#dirty})
class Cardio extends Table with Synced {
  TextColumn get type => text()();
  DateTimeColumn get startedAt => dateTime()();
  RealColumn get distanceKm => real().nullable()(); // null for sports
  IntColumn get durationSec => integer()();
  IntColumn get avgHr => integer().nullable()();
  RealColumn get inclinePct => real().nullable()();
  IntColumn get rpe => integer().nullable()();
  TextColumn get notes => text().nullable()();
  // Run columns (migration 006). `durationSec` is Moving time.
  IntColumn get elapsedSec => integer().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get source => text().nullable()(); // manual, file, health_connect, recorded
  TextColumn get externalId => text().nullable()();
  RealColumn get elevationGainM => real().nullable()();
  IntColumn get maxHr => integer().nullable()();
  RealColumn get avgCadence => real().nullable()();
  IntColumn get calories => integer().nullable()();
  TextColumn get route => text().nullable()(); // simplified polyline, about 200 points
  TextColumn get editedFields => text().map(const StringList()).withDefault(const Constant('[]'))(); // fields Daniel edited; merges never replace them
  IntColumn get steps => integer().nullable()(); // migration 007: what the treadmill showed; typed by Daniel, never measured
}

/// One row per Run: its points as gzip + base64 column arrays. See track.dart.
@TableIndex(name: 'cardio_tracks_dirty', columns: {#dirty})
class CardioTracks extends Table with Synced {
  TextColumn get cardioId => text().unique().references(Cardio, #id)();
  TextColumn get points => text()();
}

/// The single settings row (id `settingsRowId`).
@TableIndex(name: 'settings_dirty', columns: {#dirty})
@DataClassName('AppSetting')
class AppSettings extends Table with Synced {
  @override
  String get tableName => 'settings';

  IntColumn get maxHr => integer().nullable()(); // null = 220 minus age
  IntColumn get birthYear => integer().nullable()();
  RealColumn get strideM => real().nullable()(); // unused since the step counter was dropped; the column stays
  IntColumn get strideSamples => integer().nullable()(); // unused, like strideM
}

/// Local only: fastest times per Run and standard distance, rebuilt from tracks. Not synced or backed up.
class BestEfforts extends Table {
  TextColumn get cardioId => text()();
  IntColumn get distanceM => integer()();
  RealColumn get seconds => real()();

  @override
  Set<Column> get primaryKey => {cardioId, distanceM};
}

/// Local only: last pulled `server_updated_at` per synced table.
class SyncCursors extends Table {
  TextColumn get syncedTable => text()();
  DateTimeColumn get cursor => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {syncedTable};
}

/// Local only: caught errors waiting to be pushed to `app_errors`. See error_log.dart.
@DataClassName('ErrorEntry')
class ErrorLogs extends Table {
  TextColumn get id => text()();
  TextColumn get source => text()();
  TextColumn get errorType => text()();
  TextColumn get message => text()();
  TextColumn get stack => text().nullable()();
  TextColumn get context => text().withDefault(const Constant('{}'))(); // JSON object
  IntColumn get occurrences => integer().withDefault(const Constant(1))(); // `count` remotely
  DateTimeColumn get firstAt => dateTime()();
  DateTimeColumn get lastAt => dateTime()();
  TextColumn get appVersion => text().nullable()();
  TextColumn get os => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local only: the log of the live recording in progress, saved as it happens so a killed app or a restarted phone can resume it. See live_recorder.dart.
@DataClassName('RecordingEventRow')
class RecordingEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get event => text()(); // a RecorderEvent as JSON
}

@DriftDatabase(tables: [Exercises, Routines, RoutineExercises, RoutineSets, Workouts, WorkoutExercises, WorkoutSets, Cardio, CardioTracks, AppSettings, BestEfforts, SyncCursors, ErrorLogs, RecordingEvents])
class AppDb extends _$AppDb {
  AppDb([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'timburr'));

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(routineSets);
            await _addRunColumns(m); // alterTable copies the whole current definition, so the columns v7 adds must exist first
            await m.addColumn(cardio, cardio.steps);
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
          if (from < 4) await m.createTable(errorLogs);
          if (from < 5) {
            // Drop first: a file may already hold them (older test fixtures are built from today's schema).
            for (final i in allSchemaEntities.whereType<Index>().where((i) => i.entityName != 'cardio_tracks_dirty' && i.entityName != 'settings_dirty')) {
              await customStatement('DROP INDEX IF EXISTS ${i.entityName}');
              await m.createIndex(i);
            }
          }
          if (from < 6) {
            await m.addColumn(routineExercises, routineExercises.alternativeIds);
            await m.addColumn(workoutExercises, workoutExercises.alternativeIds);
            await m.addColumn(workoutExercises, workoutExercises.skipped);
            for (final t in ['routine_exercises', 'workout_exercises']) {
              await customStatement(
                  'UPDATE $t SET alternative_ids = json_array(backup_exercise_id) WHERE backup_exercise_id IS NOT NULL');
            }
          }
          if (from < 7) {
            if (from >= 2) await _addRunColumns(m);
            await m.createTable(cardioTracks);
            await m.createTable(appSettings);
            await m.createTable(bestEfforts);
            for (final i in allSchemaEntities.whereType<Index>().where((i) => i.entityName == 'cardio_tracks_dirty' || i.entityName == 'settings_dirty')) {
              await customStatement('DROP INDEX IF EXISTS ${i.entityName}');
              await m.createIndex(i);
            }
          }
          if (from < 8) await m.createTable(recordingEvents);
          if (from >= 2 && from < 9) await m.addColumn(cardio, cardio.steps); // a file older than v2 got it above
        },
        beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
      );

  Future<void> _addRunColumns(Migrator m) async {
    for (final c in [cardio.elapsedSec, cardio.title, cardio.source, cardio.externalId, cardio.elevationGainM, cardio.maxHr, cardio.avgCadence, cardio.calories, cardio.route, cardio.editedFields]) {
      await m.addColumn(cardio, c);
    }
  }

  /// Synced tables in dependency order, parents first.
  List<TableInfo> get syncedTables => [exercises, routines, routineExercises, routineSets, workouts, workoutExercises, workoutSets, cardio, cardioTracks, appSettings];

  /// The Run's track row, null when it has none or it is deleted.
  SimpleSelectStatement<$CardioTracksTable, CardioTrack> liveTrackRow(String cardioId) =>
      select(cardioTracks)..where((t) => t.cardioId.equals(cardioId) & t.deletedAt.isNull());

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
