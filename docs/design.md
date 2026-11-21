# Timburr design

## Stack

Spec: [#3](https://github.com/danielrispler/timburr/issues/3).

- Flutter + Dart, Android only (min SDK 26 for Health Connect, target 36). Replaces the Stage 1 Vite + React + Capacitor scaffold.
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
| `routine_exercises` | `routine_id`, `exercise_id`, `alternative_ids[]`, `position` |
| `routine_sets` | `routine_exercise_id`, `set_number`, `weight_kg` (used only before the exercise has a last session), `reps`, `duration_sec` |
| `workouts` | `routine_id` (nullable), `started_at`, `finished_at` (null = in progress), `notes` |
| `workout_exercises` | `workout_id`, `exercise_id`, `alternative_ids[]`, `position`, `notes`, `superset_with_next`, `skipped` |
| `sets` | `workout_exercise_id`, `set_number`, `weight_kg`, `reps`, `duration_sec`, `done` |
| `cardio` | `type` (run, treadmill; old rows may hold walk, bike, swim or sports types), `started_at`, `distance_km` (null only on old sports rows), `duration_sec`, `avg_hr`, `incline_pct`, `rpe`, `notes` |

Migration 006 (drift schema 7) adds Run data. `cardio` gains `elapsed_sec`, `title`, `source`, `external_id`, `elevation_gain_m`, `max_hr`, `avg_cadence`, `calories`, `route` and `edited_fields[]`; `duration_sec` is Moving time. `cardio_tracks` (`cardio_id` unique, `points` gzip + base64, see `lib/data/track.dart`) has one row per Run, id `uuidv5(cardio_id)`. `settings` is one row with the fixed id `settingsRowId`: `max_hr`, `birth_year`, `stride_m`, `stride_samples`. Both tables sync after `cardio`. `best_efforts` is a local-only cache, never synced or backed up.

Best efforts (`lib/data/best_efforts.dart`): the fastest time per Run at 400 m, 1 km, 1 mile, 5 km, 10 km and half marathon, by a sliding window over the track's time and distance with the window edge interpolated. Only live outdoor (`run`) Runs with a track count, so a Treadmill run never sets an effort or PR. Window rules: any gap over 30 s between raw points inside the window voids it, and so does a jump above 10 m/s (36 km/h, faster than a runner holds; some exports put the Run's total on the second point). With two or more positioned points the effort distance is the cumulative haversine over the positions, not the file's DistanceMeters, which is stale between updates and jumps when it catches up; without positions the distance column is used. Points that repeat a stale distance (watch exports that update distance every ~30 s) are skipped for the interpolation but still count for the gap check. `AppDb.rebuildBestEfforts([ids])` recomputes the cache; it runs after save, ingest, edit, delete, every sync pull of cardio or cardio_tracks rows (for those Runs) and a backup restore (all). PR = the fastest effort of all live Runs, the earlier Run on a tie.

**Recordings and ingest.** Every source builds a `Recording` (`lib/data/recording.dart`) and passes it to `CardioStore.ingest`, the only way a Run is created from one. The same `source` + `external_id` again is a no-op (a deleted Run stays deleted). A recording whose time range overlaps a Run (touching ends don't count) merges into it; otherwise it becomes a new Run, except a `health_connect` one, which is ignored (`IngestOutcome.ignored`): only Daniel creates Runs, by recording, importing a file or typing one in. Merging, per field: a field in `edited_fields` (SQL column names, set by `CardioStore.edit`) is never touched, and neither is any value on a hand-typed Run. Otherwise each field has a preferred source that may replace a value between the phone's `recorded` recording and an import (`_preferredSource` in `cardio.dart`); everything else, and any import (`file`, `health_connect`) against a value an import put on the Run, only fills an empty field. Outdoor Run: type, distance, Moving time and elevation from `recorded` (the phone's GPS), heart rate, calories and cadence from `health_connect` (the Fitbit). Treadmill run: type and Moving time from `recorded`, distance and heart rate from `health_connect`, until Daniel corrects the distance (an edit, which always wins). Notes are only ever filled. The span runs from the earliest start to the latest end (`elapsed_sec`). A `recorded` recording that merges into an imported Run becomes its `source` and `external_id`; a recording without an external id never overwrites one. The track is merged by column (`fillMissingColumns` in `track.dart`): the live recording's track is the base when there is one, and a column it lacks (heart rate, positions, altitude) is filled from the other track by nearest absolute time within 10 s, so a merge never drops a column; the other column values are never replaced. `route` is recomputed from the merged track. `route` is about 200 points as `lat,lon;lat,lon` (5 decimals), only with 50 or more positioned points.

**Live recording (outdoor).** `Recorder` (`lib/data/recorder.dart`) is a pure state machine: fixes and Pause/Resume in, a `Recording` out, no clock of its own. It drops fixes vaguer than 30 m and jumps above `maxRunSpeed`, adds distance only at 0.5 m/s or faster, and counts a stop of 5 s or more as auto-paused (the same rule as `autoPauseMovingSec`). Everything it is given is an event in `Recorder.events`; HR, laps and treadmill steps are new event kinds. `LiveRecorder` (`live_recorder.dart`) wires it to a `PositionSource` (geolocator), a `RecordingService` (flutter_foreground_task, location-type service with a wake lock) and a `RecordingJournal`: every event is appended to the local-only `recording_events` table (drift v8) as it arrives. After a kill or restart `restore()` replays the log into a recorder that is paused at its last event. Finish builds a `recorded` Recording (external id = session id) and calls `ingest`, so a later Fitbit session merges into it; Discard clears the log and saves nothing.

**Run page** (`lib/ui/cardio/run_page.dart`, opened with `openRun`). Map (OpenStreetMap tiles, cached by flutter_map, credit "© OpenStreetMap"), stats, km splits and a pace/HR/elevation chart come from the stored track; no route, no map. Analysis is pure code in `lib/data/run_analysis.dart`. A recording with no Moving time from its source gets auto-pause Moving time (below 0.5 m/s for 5 s) and a recording with no elevation gain gets one from the smoothed altitude, both at ingest and only filling empty fields. Untitled Runs show a time-of-day title by start hour: 5-10 Morning, 11-13 Lunch, 14-17 Afternoon, 18-21 Evening, 22-4 Night. The edit form saves only changed fields through `CardioStore.edit`. Delete soft-deletes the Run and its track.

**Health Connect** (`lib/data/health_connect.dart`, platform side `HealthChannel.kt` on channel `timburr/health`, read only). Connected means the exercise permission is granted; Connect (More, Fitbit) shows what Timburr reads before the system prompt, Disconnect revokes every permission, so no setting is stored. On app start, resume and Check Fitbit now (Fitbit screen, and the Runs view once connected) it reads the last 30 days of exercise sessions, each with the heart-rate samples, distance and calories (total, else active) that the session's own app wrote during it. A running or treadmill session becomes a `health_connect` recording (track of time and HR only, no Moving time) passed to ingest, which merges it into the Run it overlaps or ignores it; re-reading a session changes nothing. Every other session may fill a finished Workout's empty Health stats (avg HR, calories, active time = start to end; `WorkoutStore.fillHealth`): the Workout takes the session overlapping it most, among those with at least half their time inside it. The screenshot sheet still works, and any value already there wins. The permission-rationale intents just open the app. Routes are not read: Auto-detected runs have none.

Changes from the brief:

- **`exercises` and `exercise_settings` are merged.** A library exercise gets a row only once it is used or configured. The row's id is deterministic, `uuidv5(library_id)`, so two offline devices (or a restore into a fresh project) produce the same id, and `unique (user_id, library_id)` guards against duplicates. Every reference (`exercise_ref`) becomes a real `exercise_id` uuid foreign key. Open research: [#1](https://github.com/danielrispler/timburr/issues/1).
- **`workouts.finished` becomes `finished_at`.** History gets workout duration for free.
- **`cardio.date` becomes `started_at`.** Same name and type as on workouts.
- **`server_updated_at` is added** as the pull cursor (see Sync).
- No derived values are stored. PRs, e1RM, volume and pace are computed from sets and cardio.

## Sync

- Every local write goes through the `save(table, row)` helper, or for set edits from the workout screen the column-level `patchSet`/`stepSet`. Both set `updated_at = now()` and `dirty = 1`. `dirty` is an integer.
- Every sync runs `push`, then `pull`. Only one sync runs at a time.
- Triggers: app start, resume, finishing a workout, every 5 minutes while open, going back online, and "Sync now".
- **Push.** For each table in dependency order (exercises, routines, routine_exercises, routine_sets, workouts, workout_exercises, sets, cardio), upsert the dirty rows in chunks. The dirty rows of every table are read in one snapshot before anything is pushed, so a child saved mid-push (a track, a set) waits for the next sync with its parent. Clear `dirty` only on rows whose `updated_at` didn't change during the push, so an edit made mid-sync stays dirty.
- **Pull.** For each table in the same order, read rows where `server_updated_at` is after the table's cursor, minus a 5-second overlap. Page through them, ordered by `server_updated_at`. Apply a row only if it is new locally or its `updated_at` is newer than the local copy. Re-applying an overlapping row is a no-op.
- **Last write wins** by client `updated_at`, enforced on both sides. The server trigger ignores an update older than the stored row. The client pull ignores a remote row older than the local one. Unsynced local edits are never overwritten.
- **Deletes are soft** (`deleted_at`), so they sync like any other change.
- **Failures.** A row the server rejects is skipped, reported to the error log and stays dirty. Push continues with the remaining rows and tables, and the next trigger retries it. On a failed pull, the status shows `error` and the next trigger retries.
- **Fresh install.** After login the cursors are empty, so the first pull downloads everything.
- **Sign out** is only allowed when nothing is pending. It then wipes the local copy.
- **Status in the header:** `synced`, `N pending`, `offline`, or `error` (tap for the message).
- Supabase free projects pause after about 7 days of low activity. While paused, the app keeps working offline and sync shows `error`. Restore the project from the dashboard (possible for up to 90 days).

## Screens

Header on every screen: title, History icon, More icon and sync status. Bottom tabs: Home, Workouts, Running. Workouts has top tabs Saved, Stats, Exercises and Records. Running is a placeholder until the Runs view lands. Each tab keeps its own navigation stack. Saved routines are called "workouts" in the UI.

1. **Login.** Shown once on a fresh install. Email and password.
2. **Home.** Resume-workout banner, the backup reminder (dismissible, shown when the last export is older than 14 days), and "Start workout". That opens a list of saved workouts, Empty workout, Run and Treadmill run. Each asks **Start now** (live workout, or a timer for runs) or **I did it** (logged at a picked time, all sets done).
3. **Workout (active or past).** Editable date and time and a workout note. For each exercise card:
   - sticky note, "Last time" set list, and the one-off session note;
   - set rows with −/+ steppers (2.5 kg / 1 rep / 5 s) and tap-to-type;
   - done toggle and PR badge;
   - link-with-next (superset), up/down reorder, remove.

   Below the cards: add exercise, then finish or discard. A non-blocking rest bar appears at the bottom after a set is marked done.
4. **Exercise picker.** Search by name, filter by muscle and equipment, thumbnails, optional multi-select. Used by the workout and routine screens.
5. **Workout builder (routine editor).** Exercise cards with photo and planned sets ("3 sets • 10 reps"), swipe to delete, long-press to reorder, tap to edit sets. Bookmark names and saves it; a new one never named is deleted on leaving. Add exercises (multi-select), Start workout, I have done this workout. Finishing a workout that differs from its routine asks whether to update the routine.
6. **History** (header icon, opens over the tabs; back returns to the tab). Workouts and cardio by date, with a type filter. Opens the workout or cardio detail.
7. **Cardio form.** New or edit: type, date, distance, duration, average HR, incline, RPE, notes. Pace is computed.
8. **Exercises** (Workouts top tab). Media: the exercises-dataset thumbnail and looping GIF (© Gym visual, credited under the GIF), downloaded on first view into the cache dir (not synced or backed up); plus a YouTube search link. Library and custom exercises with search and filters. The detail page shows instructions, load type, sticky note, last session, PRs and charts. Custom exercises can be created, edited and deleted.
9. **More.** Import, Backup / Restore, Max HR, Fitbit (Health Connect), Sync now, Sign out.
10. **Stats** (Workouts top tab). One scroll: totals, streaks, heatmap, weekly charts, most trained and per-saved-workout stats. **Records** (Workouts top tab) holds PRs and all-time bests.

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

**Running tab** (`lib/ui/running/running_tab.dart`): top tabs Runs, Progress, Records (placeholder until #61). Runs: this week against the average of the 12 weeks before it, month / year / all-time totals (distance, time, count; treadmill included, other types and Workouts not), an "Import runs" entry to the Strava import, and the 20 latest Runs with a route thumbnail (the stored `route` as a plain polyline). Progress: weekly (26), monthly (24) and yearly distance bars, one bar per real period with empty ones as zero. Maths in `lib/data/running.dart`.
