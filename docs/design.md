# Timburr design (stage 1 proposal)

## Stack

- Vite + React + TypeScript, wrapped with Capacitor 8 for Android (min SDK 24, target 36).
- **Dexie (IndexedDB)** as the on-device working copy instead of `@capacitor-community/sqlite`. It runs the same in the Android WebView, the desktop browser and Vitest (`fake-indexeddb`), needs no native setup, and `liveQuery` gives reactive screens. WebView storage is app data: it is only cleared by "Clear data" or an uninstall, and both sync and backups cover that case.
- `@supabase/supabase-js` for auth and sync. Chart.js (stage 3).
- Capacitor plugins, added in the stage that needs them: `@capacitor/app` (resume, back button), `@capacitor/network`, `@capacitor/haptics`, `@capacitor/local-notifications` (stage 2); `@capacitor/filesystem` + `@capacitor/share` (stage 4).
- No router dependency: a ~30-line hash router. The Android back button maps to `history.back()`.
- Plain CSS, dark only. Exercise reordering uses up/down buttons, not drag.

## Data model

All tables live in `supabase/migrations/001_init.sql`, mirrored in Dexie with the same names and columns.

Common columns: `id` (client uuid), `user_id`, `created_at`, `updated_at`, `deleted_at`, `server_updated_at`.

| Table | Columns |
| --- | --- |
| `exercises` | `library_id` (null = custom), `name` (custom only), `load_type`, `muscles[]`, `equipment`, `sticky_note`, `last_rest_sec` |
| `routines` | `name`, `sticky_note` |
| `routine_exercises` | `routine_id`, `exercise_id`, `position` |
| `workouts` | `routine_id` (nullable), `started_at`, `finished_at` (null = in progress), `notes` |
| `workout_exercises` | `workout_id`, `exercise_id`, `position`, `notes`, `superset_with_next` |
| `sets` | `workout_exercise_id`, `set_number`, `weight_kg`, `reps`, `duration_sec`, `done` |
| `cardio` | `type`, `started_at`, `distance_km`, `duration_sec`, `avg_hr`, `incline_pct`, `rpe`, `notes` |

Changes from the brief:

- **`exercises` and `exercise_settings` are merged.** A library exercise gets a row only once it is used or configured. The row's id is deterministic, `uuidv5(library_id)`, so two offline devices (or a restore into a fresh project) produce the same id, and `unique (user_id, library_id)` guards against duplicates. Every reference (`exercise_ref`) becomes a real `exercise_id` uuid foreign key. Open research: [#1](https://github.com/danielrispler/timburr/issues/1).
- **`workouts.finished` becomes `finished_at`.** History gets workout duration for free.
- **`cardio.date` becomes `started_at`.** Same name and type as on workouts.
- **`server_updated_at` is added** as the pull cursor (see Sync).
- No derived values are stored. PRs, e1RM, volume and pace are computed from sets and cardio.

## Sync

- Every local write goes through one `save(table, row)` helper. It sets `updated_at = now()` and `dirty = 1`. IndexedDB cannot index booleans, so `dirty` is a number.
- Every sync runs `push`, then `pull`. Only one sync runs at a time.
- Triggers: app start, resume, finishing a workout, every 5 minutes while open, going back online, and "Sync now".
- **Push.** For each table in dependency order (exercises, routines, routine_exercises, workouts, workout_exercises, sets, cardio), upsert the dirty rows in chunks. Clear `dirty` only on rows whose `updated_at` didn't change during the push, so an edit made mid-sync stays dirty.
- **Pull.** For each table in the same order, read rows where `server_updated_at` is after the table's cursor, minus a 5-second overlap. Page through them, ordered by `server_updated_at`. Apply a row only if it is new locally or its `updated_at` is newer than the local copy. Re-applying an overlapping row is a no-op.
- **Last write wins** by client `updated_at`, enforced on both sides. The server trigger ignores an update older than the stored row. The client pull ignores a remote row older than the local one. Unsynced local edits are never overwritten.
- **Deletes are soft** (`deleted_at`), so they sync like any other change.
- **Failures.** On a failed push or pull, rows stay dirty, the status shows `error`, and the next trigger retries. Sync stops at the first failing table, because its children would fail the foreign key anyway.
- **Fresh install.** After login the cursors are empty, so the first pull downloads everything.
- **Sign out** is only allowed when nothing is pending. It then wipes the local copy.
- **Status in the header:** `synced`, `N pending`, `offline`, or `error` (tap for the message).
- Supabase free projects pause after about 7 days of low activity. While paused, the app keeps working offline and sync shows `error`. Restore the project from the dashboard (possible for up to 90 days).

## Screens

Header on every screen: title and sync status. Bottom tabs: Home, History, Exercises, More.

1. **Login.** Shown once on a fresh install. Email and password.
2. **Home.** Resume-workout banner, Start empty, routines (start, edit, new), Log cardio, and the backup reminder (dismissible, shown when the last export is older than 14 days).
3. **Workout (active or past).** Editable date and time and a workout note. For each exercise card:
   - sticky note, "Last time" set list, and the one-off session note;
   - set rows with −/+ steppers (2.5 kg / 1 rep / 5 s) and tap-to-type;
   - done toggle and PR badge;
   - link-with-next (superset), up/down reorder, remove.

   Below the cards: add exercise, then finish or discard. A non-blocking rest bar appears at the bottom after a set is marked done.
4. **Exercise picker.** Search by name, filter by muscle and equipment. Used by the workout and routine screens.
5. **Routine editor.** Name, sticky note, and an ordered exercise list.
6. **History.** Workouts and cardio by date, with a type filter. Opens the workout or cardio detail.
7. **Cardio form.** New or edit: type, date, distance, duration, average HR, incline, RPE, notes. Pace is computed.
8. **Exercises.** Library and custom exercises with search and filters. The detail page shows instructions, load type, sticky note, last session, PRs and charts. Custom exercises can be created, edited and deleted.
9. **More.** Cardio stats, Import, Backup / Restore, Sync now, Sign out.

## Defaults decided during planning

- Weight in kg, distance in km.
- One global set of step sizes.
- PR badge:
  - compared against previous workouts only;
  - no badge the first time an exercise is done;
  - ties don't count;
  - only the session's best set shows the badge;
  - a 1-rep set's e1RM is the weight itself.
- The rest-timer notification vibrates only and uses `USE_EXACT_ALARM`.
- "Copy import format" lists only custom exercises and exercises used at least once.
- Backup restore:
  - "replace" soft-deletes every row that isn't in the backup, so it can be undone;
  - "merge" upserts by id, last write wins.
- Releases build only on a `v*` tag. `versionCode` is the CI run number.
