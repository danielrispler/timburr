# Original brief

Daniel's requirements, verbatim from session 1. Where [design.md](design.md) or the spec ([#3](https://github.com/danielrispler/timburr/issues/3)) differs, they win. Notably the stack is now Flutter + Dart, not React/Capacitor/TypeScript.

---

Build me a personal Android workout-logging app (installable APK) backed by my own Supabase project. Work in stages and stop for my approval after stage 1.

## Goals and constraints
- Android APK for my own phone. No ads, no analytics, no third-party services except my own Supabase project.
- UI entirely in English, mobile-first, clean and fast to use mid-workout with one hand (large tap targets, minimal typing).
- Simple, readable, safe code. No over-engineering. TypeScript throughout.
- Offline-first: the app must work fully without internet (gyms often have bad reception) and sync to Supabase when online.
- Suggested stack: Vite + React + TypeScript, wrapped with Capacitor for Android. Local SQLite via @capacitor-community/sqlite as the on-device working copy, @supabase/supabase-js for sync, a light chart library (e.g. Chart.js). If you think something simpler is better, propose it in stage 1.

## Supabase
- Write a migration file (supabase/migrations/001_init.sql) with all tables, indexes and Row Level Security.
- Every table has: id uuid primary key (generated on the client), user_id uuid references auth.users, created_at, updated_at, deleted_at (soft delete, nullable).
- RLS on every table: a user can select/insert/update/delete only rows where user_id = auth.uid().
- Auth: email + password, single user (me). Tell me how to create my user and then disable new sign-ups in the dashboard.
- The app only ever uses the anon/publishable key. Never put the service_role key in the app or the repo.
- Supabase URL and anon key come from build-time env vars (.env, git-ignored; repository secrets in CI).
- Give me short step-by-step setup instructions: create project, run the migration, create my user, disable sign-ups, fill .env.

## Sync (keep it simple)
- All reads and writes go to local SQLite first, so the UI is instant and works offline.
- Changed rows are marked dirty. When online (on app start, on resume, after finishing a workout, and every few minutes while open), push dirty rows with upsert, then pull rows changed since the last successful pull (by updated_at).
- Conflicts: last write wins by updated_at. Deletes are soft (deleted_at) so they sync.
- Single user, usually one device, so no realtime subscriptions and no complex merge logic.
- Show a small sync status (synced / N pending / offline / error) in the header or settings, and a manual "Sync now" button.
- Never lose local changes because a sync failed; retry later.
- On a fresh install, after login, pull everything from Supabase.

## Exercise library
- Bundle the open exercise dataset from https://github.com/yuhonas/free-exercise-db (dist/exercises.json, public domain / Unlicense, ~870 exercises) inside the app; do not upload it to Supabase.
- Keep: name, category, equipment, primaryMuscles, secondaryMuscles, instructions. Skip images to keep the APK small.
- Search by name, filter by muscle and equipment.
- I can add my own custom exercises and edit/delete them.
- Each exercise has a load type:
  - weighted: weight (kg) x reps
  - bodyweight: reps, with optional added weight (kg)
  - timed: duration (e.g. plank)
- Each exercise has an optional sticky note (e.g. "seat height 4") that persists until I change it and is shown every time the exercise appears in a workout.
- Store in Supabase only my custom exercises and my settings for library exercises (load type override, sticky note, last rest duration), referenced by the library id.

## Routines (workout templates)
- Create, edit, delete routines: a name, an ordered list of exercises, and an optional sticky note shown whenever I start that routine.

## Logging a strength workout
- Start from a routine or start empty. Add, remove and reorder exercises during the workout.
- Next to each exercise show "Last time": the full set list from the most recent session of that exercise (e.g. 70x10, 80x8, 90x6), not just the max.
- Every set stores its own weight and reps (or duration), because I often ramp up across sets (70, 80, 90).
- Fast set entry: new sets prefill from the previous set or from last time; tap to mark a set done.
- Autosave every change locally so nothing is lost if the app closes. An unfinished workout resumes when I reopen the app.
- Workout date/time is editable so I can log past workouts.
- Supersets: a "link with next exercise" toggle during the workout; linked exercises are displayed as a group. Must work spontaneously mid-workout.
- Notes: an optional one-off note per exercise in this session and per whole workout, saved in history (separate from the sticky notes above).

## Rest timer (must not be annoying)
- After I mark a set done, show a small non-blocking bar at the bottom with 4 buttons: 1:00, 1:30, 2:00, 2:30.
- If I tap one, it counts down in that bar. If I ignore it, it hides after a few seconds. Never a modal or popup.
- Remember the last chosen duration per exercise and highlight it.
- When the timer ends: vibrate, plus a local notification so it works with the screen off (Capacitor Local Notifications).

## Personal records
- Per exercise:
  - weighted: heaviest weight, best estimated 1RM (Epley: weight x (1 + reps/30)), best session volume
  - bodyweight: max reps (and max added weight)
  - timed: longest duration
- Show a PR badge immediately during the workout when a set beats a record.

## Cardio (manual entry only, no live tracking)
- Types: run, walk, treadmill, bike.
- Required: type, date, distance (km), duration.
- Optional: average heart rate, incline (%), effort (RPE 1-10), notes.
- Computed: pace (min/km).
- Cardio stats: list of sessions, filter by type and distance range (e.g. ~5 km, ~10 km), best time per distance bucket, pace trend chart.

## Stats
- Per exercise: last session, PRs, and line charts over time of max weight, estimated 1RM and total volume.
- History: list of all workouts by date; tap to see every exercise, set and note.

## Import (for adding workouts from screenshots via a chat assistant)
- An "Import" screen with a text box where I paste JSON in the format below, then a preview table where I can fix any cell, then confirm to save.
- Match exercise names case-insensitively against the library and my custom exercises. For unknown names, let me pick an existing exercise or create a new one before saving.
- A "Copy import format" button that copies a short description of this format plus my list of exercise names, so I can paste it to the assistant together with a screenshot.
- Validate strictly and show clear errors; never save partial or invalid data.

Import format:

```json
{
  "version": 1,
  "workouts": [
    {
      "date": "2026-10-24T16:13",
      "routine": "Push A",
      "notes": "",
      "exercises": [
        {
          "name": "Barbell Bench Press - Medium Grip",
          "notes": "",
          "supersetWithNext": false,
          "sets": [
            { "weightKg": 70, "reps": 10 },
            { "weightKg": 80, "reps": 8 },
            { "weightKg": 90, "reps": 6 }
          ]
        }
      ]
    }
  ],
  "cardio": [
    {
      "type": "run",
      "date": "2026-10-23T17:15",
      "distanceKm": 5.0,
      "durationSec": 1680,
      "avgHr": 158,
      "inclinePct": null,
      "rpe": 7,
      "notes": ""
    }
  ]
}
```

For bodyweight sets weightKg is the added weight (or null). Timed sets use "durationSec" instead of "reps". "routine" is optional.

## Backup and restore (independent of Supabase)
- "Export backup": write all data to a single JSON file and open the Android share sheet so I can save it to Google Drive or Files.
- "Restore backup": pick a backup file and restore it (into local storage and then Supabase), with a clear choice between replace and merge, and a confirmation step.
- If the last export is older than 14 days, show a small dismissible reminder on the home screen. Never a popup.
- The backup format must be enough to rebuild everything in a fresh Supabase project.

## Data model (adjust if needed, explain changes)
- exercises (custom only): id, name, load_type, muscles, equipment, sticky_note, last_rest_sec
- exercise_settings (for library exercises): id, library_id, load_type, sticky_note, last_rest_sec
- routines: id, name, sticky_note
- routine_exercises: id, routine_id, exercise_ref, position
- workouts: id, started_at, routine_id (nullable), notes, finished (bool)
- workout_exercises: id, workout_id, exercise_ref, position, notes, superset_with_next
- sets: id, workout_exercise_id, set_number, weight_kg, reps, duration_sec, done
- cardio: id, type, date, distance_km, duration_sec, avg_hr, incline_pct, rpe, notes

(exercise_ref points to either a custom exercise id or a library id; choose a clean way to model this.)
Plus the common columns from the Supabase section. Compute PRs and stats from these tables; don't store derived values unless needed for speed.

## Build and install
- Build a release APK I can sideload.
- Create one signing keystore and use it for every build, so updates install over the previous version. Keep the keystore and passwords out of git and tell me where to back them up.
- Add a GitHub Actions workflow that builds the signed APK (keystore and Supabase env vars from repository secrets) and attaches it to a GitHub Release, so I can download updates from my phone.
- Give me short step-by-step instructions for building and installing.

## Testing
- Unit tests for the pure logic: PR detection, 1RM, volume, pace, import validation and exercise matching, sync dirty/push/pull logic, backup round-trip.

## Stages
1. Scaffold the project, write the Supabase migration, propose the final data model, sync design and screen list, and show me. Wait for my approval.
2. Auth, local storage and sync, exercise library, routines, and workout logging with rest timer, supersets and notes.
3. PRs and stats screens, cardio entry and cardio stats.
4. Import, backup/restore, signed build and GitHub Actions workflow.

After each stage, summarize what was done and what I should test on my phone.
