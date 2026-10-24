# Timburr design

## Stack

Spec: [#3](https://github.com/danielrispler/timburr/issues/3).

- Flutter + Dart, Android only (min SDK 24, target 36). Replaces the Stage 1 Vite + React + Capacitor scaffold.
- **drift (SQLite)** as the on-device working copy. Reactive `watch` queries drive the screens, and tests use an in-memory database.
- `supabase_flutter` for auth and sync. `fl_chart` for charts (stage 3).
- Plugins, added in the stage that needs them: `connectivity_plus`, `flutter_local_notifications` (stage 2); `share_plus`, `file_picker`, `path_provider` (stage 4). `uuid` for v4 and v5 ids.
- Supabase URL and publishable key come from `--dart-define-from-file` with a git-ignored env file.
- Built-in `Navigator` and a bottom `NavigationBar`. No router or state-management package.
- Material 3, dark only. Exercise reordering uses up/down buttons, not drag.

## Data model

All tables live in `supabase/migrations/001_init.sql`, mirrored in drift with the same names and columns, plus a local-only `dirty` flag and per-table pull cursors.

Common columns: `id` (client uuid), `user_id`, `created_at`, `updated_at`, `deleted_at`, `server_updated_at`.

| Table | Columns |
| --- | --- |
| `exercises` | `library_id` (null = custom), `name` (custom only), `load_type`, `muscles[]`, `equipment`, `sticky_note`, `last_rest_sec` |
| `routines` | `name`, `sticky_note` |
| `routine_exercises` | `routine_id`, `exercise_id`, `position` |
| `routine_sets` | `routine_exercise_id`, `set_number`, `weight_kg` (null = last session's), `reps`, `duration_sec` |
| `workouts` | `routine_id` (nullable), `started_at`, `finished_at` (null = in progress), `notes` |
| `workout_exercises` | `workout_id`, `exercise_id`, `position`, `notes`, `superset_with_next` |
| `sets` | `workout_exercise_id`, `set_number`, `weight_kg`, `reps`, `duration_sec`, `done` |
| `cardio` | `type` (run, walk, treadmill, bike, swim, padel, tennis, soccer, basketball), `started_at`, `distance_km` (null for sports), `duration_sec`, `avg_hr`, `incline_pct`, `rpe`, `notes` |

Changes from the brief:

- **`exercises` and `exercise_settings` are merged.** A library exercise gets a row only once it is used or configured. The row's id is deterministic, `uuidv5(library_id)`, so two offline devices (or a restore into a fresh project) produce the same id, and `unique (user_id, library_id)` guards against duplicates. Every reference (`exercise_ref`) becomes a real `exercise_id` uuid foreign key. Open research: [#1](https://github.com/danielrispler/timburr/issues/1).
- **`workouts.finished` becomes `finished_at`.** History gets workout duration for free.
- **`cardio.date` becomes `started_at`.** Same name and type as on workouts.
- **`server_updated_at` is added** as the pull cursor (see Sync).
- No derived values are stored. PRs, e1RM, volume and pace are computed from sets and cardio.

## Sync

- Every local write goes through one `save(table, row)` helper. It sets `updated_at = now()` and `dirty = 1`. `dirty` is an integer.
- Every sync runs `push`, then `pull`. Only one sync runs at a time.
- Triggers: app start, resume, finishing a workout, every 5 minutes while open, going back online, and "Sync now".
- **Push.** For each table in dependency order (exercises, routines, routine_exercises, routine_sets, workouts, workout_exercises, sets, cardio), upsert the dirty rows in chunks. Clear `dirty` only on rows whose `updated_at` didn't change during the push, so an edit made mid-sync stays dirty.
- **Pull.** For each table in the same order, read rows where `server_updated_at` is after the table's cursor, minus a 5-second overlap. Page through them, ordered by `server_updated_at`. Apply a row only if it is new locally or its `updated_at` is newer than the local copy. Re-applying an overlapping row is a no-op.
- **Last write wins** by client `updated_at`, enforced on both sides. The server trigger ignores an update older than the stored row. The client pull ignores a remote row older than the local one. Unsynced local edits are never overwritten.
- **Deletes are soft** (`deleted_at`), so they sync like any other change.
- **Failures.** On a failed push or pull, rows stay dirty, the status shows `error`, and the next trigger retries. Sync stops at the first failing table, because its children would fail the foreign key anyway.
- **Fresh install.** After login the cursors are empty, so the first pull downloads everything.
- **Sign out** is only allowed when nothing is pending. It then wipes the local copy.
- **Status in the header:** `synced`, `N pending`, `offline`, or `error` (tap for the message).
- Supabase free projects pause after about 7 days of low activity. While paused, the app keeps working offline and sync shows `error`. Restore the project from the dashboard (possible for up to 90 days).

## Screens

Header on every screen: title and sync status. Bottom tabs: Home, History, Workouts, More. Saved routines are called "workouts" in the UI.

1. **Login.** Shown once on a fresh install. Email and password.
2. **Home.** Resume-workout banner, the backup reminder (dismissible, shown when the last export is older than 14 days), and "Start workout". That opens a list of saved workouts, Empty workout and the activities. Each asks **Start now** (live workout, or a timer for activities) or **I did it** (logged at a picked time, all sets done).
3. **Workout (active or past).** Editable date and time and a workout note. For each exercise card:
   - sticky note, "Last time" set list, and the one-off session note;
   - set rows with −/+ steppers (2.5 kg / 1 rep / 5 s) and tap-to-type;
   - done toggle and PR badge;
   - link-with-next (superset), up/down reorder, remove.

   Below the cards: add exercise, then finish or discard. A non-blocking rest bar appears at the bottom after a set is marked done.
4. **Exercise picker.** Search by name, filter by muscle and equipment, thumbnails, optional multi-select. Used by the workout and routine screens.
5. **Workout builder (routine editor).** Exercise cards with photo and planned sets ("3 sets • 10 reps"), swipe to delete, long-press to reorder, tap to edit sets. Bookmark names and saves it; a new one never named is deleted on leaving. Add exercises (multi-select), Start workout, I have done this workout. Finishing a workout that differs from its routine asks whether to update the routine.
6. **History.** Workouts and cardio by date, with a type filter. Opens the workout or cardio detail.
7. **Cardio form.** New or edit: type, date, distance, duration, average HR, incline, RPE, notes. Pace is computed.
8. **Exercises** (under More). Media: the exercises-dataset thumbnail and looping GIF (© Gym visual, credited under the GIF), downloaded on first view into the cache dir (not synced or backed up); plus a YouTube search link. Library and custom exercises with search and filters. The detail page shows instructions, load type, sticky note, last session, PRs and charts. Custom exercises can be created, edited and deleted.
9. **More.** Exercises, Cardio stats (sports: time and sessions per week), Import, Backup / Restore, Sync now, Sign out.

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
