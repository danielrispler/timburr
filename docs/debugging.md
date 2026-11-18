# Debugging with real data and sync

Reach for this when a bug depends on Daniel's actual data or on sync.

## Get the real data

- Supabase copy: `python3 -I tool/pull_data.py`, then `python3 -I tool/analyze.py .data/supabase.json [ROUTINE_REGEX] [EXERCISE_REGEX]`. Both are read-only. `.data/` is git-ignored.
- Phone copy: the in-app "Export backup" file. It holds the phone's own data, unsynced rows included. `analyze.py` reads it too.

## Replay it in a throwaway test

Restore the data into an in-memory db, then call the real store methods. Delete the test afterwards.

```dart
final db = AppDb(NativeDatabase.memory());
await Backup(db).restore(
    jsonEncode({'format': Backup.format, 'version': Backup.version, 'tables': tables}),
    replace: false);
```

## Reading the data

- Routine plan history survives. `RoutineStore.replacePlan` soft-deletes the old `routine_exercises` and their `routine_sets` and appends new rows, so every plan version is recoverable from `created_at` / `deleted_at`.
- Imported workouts have `finished_at == started_at` (`lib/data/importer.dart`). "I did it" workouts finish at start + `estimateDuration` (`lib/data/workouts.dart`).
- Library exercises may carry legacy ids. Map them through `legacyIds` in `assets/exercises.json`, as `lib/data/catalog.dart` does.

## Sync

- Phone errors land in Supabase `app_errors` (`supabase/migrations/004_app_errors.sql`): source, error_type, message, count, first_at, last_at, app_version.
- Header cloud-off icon "Not synced" means the build had no `.env.json` defines (`lib/ui/core/app_shell.dart`). Build with `tool/phone.sh`. A failed sync shows "error" instead; tap it for the message (`lib/ui/sync/sync_ui.dart`).
- A server-side data change reaches the phone only when its `updated_at` is newer than the local row (merge in `lib/data/sync.dart`). Bump `updated_at` when patching rows on the server.
