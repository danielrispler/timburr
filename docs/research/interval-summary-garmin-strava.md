# Interval-run summary: what Garmin and Strava show, and what Timburr can copy

Question: how do Garmin Connect and Strava summarise an interval run, and which parts can Timburr build from the data it already records?

Inputs:
- A screen recording of Garmin Connect (Hebrew UI, 27 Nov 2026, 22 frames at 1 fps).
- A second screen recording, which turned out to be Strava's 3D flyover replay of the same run (13 frames).
- Four Strava screenshots of the same run.

The two apps show the same activity: 5.64 km, 422 Cal and 35:50 moving time match on both (Garmin frame `g/f005`, Strava screenshot `19.08.43 (2)`). The athlete's Garmin workout was a ladder of 3:00 / 2:00 / 1:00 / 0:30 steps, repeated, after a warm-up.

Labels used on every claim:
- **[frame]**: seen in a video frame or screenshot (named).
- **[repo]**: `file:line` in this repo.
- **[official]**: Garmin or Strava developer docs, Garmin manuals, Strava support.
- **[sdk]**: Garmin's FIT profile as shipped in `garmin/fit-javascript-sdk` `src/profile.js`.
- **[forum]**: a community post.
- **[unverified]**: inference or general knowledge, with a confidence.

Frames are kept in `/private/tmp/claude-501/-Users-danielrispler-work-timburr/25950ed8-3e95-4caf-aefc-8b6cd41f2ad8/scratchpad/frames/{g,s,sheets}`. The scratchpad is temporary.

## 1. What the Garmin Connect summary shows

The activity page has five tabs: Overview, Stats, Intervals, Graphs, Gear [frame g/f001].

**Overview** [frame g/f001–f003]
- Map with the route coloured by pace on a slow-to-fast colour scale.
- Distance 5.64 km, Avg pace 6:22 /km, Avg HR 163 bpm, Total time 35:52, 422 Cal.
- Feel ("Normal") and perceived effort ("7/10, very hard").
- Workout execution score "Good, 100%". This score exists only for structured running or cycling workouts. Warm-up and recovery steps weigh less in it, and the cool-down does not count [official, fenix 8 manual](https://www8.garmin.com/manuals-apac/webhelp/fenix8series/EN-SG/GUID-F9FAB659-F4F4-47AF-AFB9-0FD8EC2B057B-9736.html).
- Device: fenix 7 Pro.

**Intervals tab: the per-step table** [frame g/f008, f009, f010, f011]
- Columns: Interval #, Type, Time, Distance (km), Avg pace (min/km).
- Filter chips by step type: All / Warm-up / Run. Only the types present in this workout appear. An "Expand" toggle opens more columns.
- The warm-up row has no number. Every step after it is numbered 1, 2, 3… and the list runs to at least 19.
- Times have tenths, e.g. 3:09.2 for the warm-up and 3:00.0 for step 1.
- Repeats are written out flat: there is no grouping header per round. You can see the repeats only from the pattern: 3:00 at 8:22, 2:00 at 4:56, 1:00 at 7:36, 0:30 at 3:39, then again.
- **Every step after the warm-up is typed "Run" (ריצה), including the slow 3:00 and 1:00 recoveries.** Garmin shows the type the workout step was given, not how hard it was run. Forum users report the same: "Warm-Ups and Cool-Downs are still classified as Run" [forum](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/293747/coach-workouts-warm-up-and-cool-down-steps-broken).
- Picking a filter adds a **Total** row ("סך הכול") for that type: with Warm-up selected it reads 3:09.2 · 0.50 km · 6:19 [frame g/f011].

**Stats tab** [frame g/f004–f007]
- Pace: avg 6:22, avg moving, grade-adjusted 6:19, best 2:46.
- Speed.
- Timing: total 35:52, moving 35:50, elapsed 35:52.
- Run/walk detection: run 35:16, walk 0:36.
- HR: avg 163, max 201, recovery HR 72.
- Stamina: start 98%, end 69%, minimum 32%.
- Training Effect: aerobic 3.4, anaerobic 2.8, primary benefit "Tempo (high-intensity aerobic)", training load 149.
- Power: avg 274 W, max 596 W.
- Running dynamics: cadence 158/197, stride 0.97 m, vertical ratio 9.6%, vertical oscillation 8.7 cm, ground contact 278 ms.
- Elevation: +25 / −28 m, min 1 m, max 11 m.
- **Interval totals for the "Run" type**: run time 32:43, run distance 5.14 km, run pace 6:22. This is the per-type average, over every step typed Run [frame g/f007].
- Nutrition: 50 resting + 372 active = 422 Cal, sweat loss 575 ml.
- Body Battery: −7.

**Graphs tab** [frame g/f012–f022, sheet g2], each with a time/distance toggle:
- Pace area chart (avg 6:22, best 2:46). The interval blocks are visible as square waves.
- HR area chart (avg 163, max 201).
- Cadence scatter, coloured by cadence band.
- Stride length.
- Ground contact time, coloured.
- Run/walk timeline.
- Time in HR zones: 5 bands, each with its bpm range, a label, minutes and %.
- Time in power zones.
- Training Effect gauges.
- Elevation (min/max).

Not seen in the frames: a cool-down row (the recording stops at step 19), a chart that marks the steps, and per-step HR in the default columns. "Expand" may add HR and other columns; this was not opened in the video [unverified, medium].

## 2. What Strava shows, and where it comes from

**Summary** [frame `19.08.43 (2)`]: map, then Distance 5.64 km, Avg pace 6:21 /km, Moving time 35:50, Elevation gain 24 m, 422 Cal, Avg cadence 161 spm. Below them is an "Athlete Intelligence" text card.

**Splits** [frame `19.08.43 (1)`]: a table with one row per km (Km, Pace, a horizontal bar whose length grows with speed, and Elev). The last row is the 0.6 km remainder. Splits are built by Strava from the recording, not from device laps. The API's `splits_metric` is "The splits of this activity in metric units (for runs)", and each split carries `distance`, `elapsed_time`, `elevation_difference`, `moving_time`, `average_speed` and `pace_zone` [official, Strava API reference](https://developers.strava.com/docs/reference/).

**Pace chart** [frame `19.08.43 (1)`]: pace in blue over a grey series, against distance (km). The grey series is elevation (per the task brief; matches Strava's usual layout) [unverified, medium].

**Laps screen** [frames `19.08.42`, `19.08.43`]
- A bar chart of laps: bar width is the lap's duration and bar height its pace (faster is higher). Bars are shaded light to dark blue by intensity. Slow laps are short pale grey bars. The dark grey silhouette behind the bars has the same shape as the Pace chart's grey series [frame; the silhouette reading is unverified, medium].
- Tapping a bar sets the header, e.g. "Lap 2 · 8:22 /km · Zone 1 · Recovery".
- Below the chart is a list: lap #, distance, time, pace. Examples: 9 · 0.15 km · 30s · 3:13/km; 17 · 0.15 km · 30s · 3:17/km; 18 · 0.26 km · 3:00 · 11:09/km.

Where the laps come from:
- **The laps are the FIT file's Lap messages, one per workout step.** The FIT activity spec says: "When performing a workout during an activity, the device will typically include a Lap message for each workout step completed, and the Lap message's Workout Step Index field will contain the index in to the list of Workout Step messages" [official, FIT Activity file](https://developer.garmin.com/fit/articles/file-types/activity.html). Strava's lap numbers are Garmin's step numbers plus one, because Strava counts the warm-up as Lap 1. For example, Strava lap 2 (3:00, 8:22) is Garmin interval 1 (3:00.0, 8:22), and Strava lap 10 (3:00, 9:34) is Garmin interval 9 (3:00.0, 9:34) [frame g/f008 vs `19.08.42`].
- The API's Lap object has `lap_index`, `split`, `elapsed_time`, `moving_time`, `distance`, `average_speed`, `start_index`/`end_index` ("The start index of this effort in its activity's stream") and `pace_zone` ("The athlete's pace zone during this lap") [official, Strava API reference](https://developers.strava.com/docs/reference/).
- Workout Analysis appears "for most activities with at least two laps". Laps come from "a GPS device that can record laps" or from the app's Lap button. Without laps, Strava shows "a Pace Analysis that breaks the activity down into one-mile or one-km laps" [official, Strava support](https://support.strava.com/hc/en-us/articles/115001136770-Mobile-Workout-Analysis).

**Where "Zone 1 · Recovery" comes from: not the file.**
- Strava's pace zones are "Zone 1: Recovery", Endurance, Tempo, Threshold, VO₂ Max, "Zone 6: Anaerobic". They are set from "a recent race or time trial result", or estimated "based on your Performance Predictions" for subscribers [official, Strava Training Zones](https://support.strava.com/hc/en-us/articles/39113532401421-Training-Zones-on-Strava).
- So "Zone 1 · Recovery" is the lap's **pace zone**: Strava's own classification of the lap's average pace against the athlete's zones, exposed as `Lap.pace_zone` [official, API].
- It is not the FIT lap `intensity`. Garmin typed that same lap "Run", not recovery [frame g/f008]. If the label had come from the file it would say Run/active. The FIT `intensity` enum is active, rest, warmup, cooldown, recovery, interval, other [sdk, `profile.js` `intensity` (line 27896 of the downloaded copy)]. The bar shading follows the same pace zones [inference, high].
- Confidence that the label is pace-zone derived and not from the file: **high**. The evidence is the "Run" vs "Recovery" mismatch on the same lap, plus Strava's zone names.

**FIT fields that matter for a Timburr importer** [sdk, `profile.js`]
- The `lap` message (num 19) has `intensity`, `lapTrigger` (manual, time, distance, positionStart, positionLap, positionWaypoint, positionMarked, sessionEnd, fitnessEquipment) and `wktStepIndex`, alongside `totalTimerTime`, `totalDistance`, `avgHeartRate` and `enhancedAvgSpeed`.
- The `split` message (num 312) has a `splitType` enum that includes `intervalActive`, `intervalRest`, `intervalWarmup`, `intervalCooldown`, `intervalRecovery`, `rwdRun` and `rwdWalk`. That last pair is likely the source of Garmin's run/walk numbers [unverified, medium].

**Strava 3D flyover (second video)** [frames s/f002–f013]: a satellite 3D camera follows the route. A header shows live Pace, Elevation and Distance, with a play/pause scrubber and a 1x/2x speed control. The route is drawn in orange behind a moving marker.

## 3. What Timburr already has

All claims here are verified against the repo.

| Data | Status | Evidence |
| --- | --- | --- |
| Per-point time, distance, lat, lon, altitude, HR, cadence columns | stored, gzip JSON in `cardio_tracks.points` | `lib/data/track.dart:22-37`; `supabase/migrations/006_runs.sql` |
| Altitude on live runs | recorded from the GPS fix | `lib/data/recorder.dart:242`, `:533` |
| HR on live runs | from the Fitbit Air over BLE, else filled from Health Connect | `recorder.dart:533` (`_hrCol`); `docs/design.md` (Recordings and ingest) |
| **Cadence on live runs** | **missing**: `_gpsTrack` builds no cadence column, and the Health Connect read takes HR, distance and calories only | `recorder.dart:533`; `docs/design.md` (Health Connect) |
| **Step boundaries + kind** of an Interval run | **stored**: `Track.steps` = `StepMark(kind, startSec, endSec, sec, meters)`, kind ∈ warmup/rep/recovery/cooldown | `lib/data/intervals.dart:9`, `:247-265`; `track.dart:31,36` |
| Steps survive a merge with Health Connect or a file | yes, shifted with the base track | `track.dart:131` |
| The plan the run followed (Repeats, target per step, target pace) | `cardio.interval_plan` jsonb copy + `interval_plan_id` | `supabase/migrations/010_intervals.sql`; `intervals.dart:64-93` |
| Manual Lap marks | `Track.laps` (seconds); on an Interval run, Next replaces the Lap button | `track.dart:30`; `lib/ui/running/record_screen.dart:49` |
| Per-step avg HR | computed | `lib/data/run_analysis.dart:220-231` |
| Rep summary (avg rep pace, fastest rep) | computed, shown in plan history | `intervals.dart:290-305`; `lib/ui/running/interval_plans.dart:683-692` |
| Per-plan "Last time" per step | computed | `intervals.dart:217-243` |
| Km splits with avg HR | computed and shown | `run_analysis.dart:32-64`; `lib/ui/cardio/run_page.dart:151-159` |
| Pace / HR / elevation chart over distance | `fl_chart` LineChart | `run_page.dart:241-281`; `run_analysis.dart:120-160` |
| HR zones (5 equal bands of max HR) | ZoneBar on the Run page | `lib/data/hr_zones.dart`; `lib/ui/cardio/max_hr.dart:72` |
| Relative Effort / load | computed | `run_page.dart:124-129` (`load.dart`) |
| Run page step list today | "Reps" list: label, km · time · pace, avg HR; non-reps greyed | `interval_plans.dart:705-763` |
| Chart package | `fl_chart: ^1.3.0`, BarChart already used; no CustomPainter anywhere in `lib/` | `pubspec.yaml:14`; `running_tab.dart:267`, `stats_screen.dart:277` |
| Imported interval runs (Strava TCX/GPX) | laps are flattened: TCX `<Lap>` is used only to stitch distance, with no steps or laps kept | `lib/data/strava_tcx.dart:20-39` |
| FIT import | none (no FIT parser in pubspec) | `pubspec.yaml` |
| Power, running dynamics, stamina, Training Effect | none, and no sensor provides them | design.md: the Fitbit Air shares HR only |
| Pace zones / threshold pace setting | none (`settings` has max_hr, birth_year) | `006_runs.sql`; `hr_zones.dart` |
| Race predictions (Riegel from Best efforts) | exist, could seed pace zones | `lib/data/predictor.dart:1-25` |

The key point: **the interval summary needs almost no new storage.** Step boundaries, step kind, the plan with its Repeats and targets, and per-point pace/HR/altitude are all already in `cardio_tracks.points` and `cardio.interval_plan`. Anything added to `StepMark` lives inside that gzip JSON blob, so it needs no SQL migration and no drift schema bump. It only needs `fromJson` to tolerate old entries.

## 4. Feature table

"Needs" spells out drift schema / Supabase migration / chart work when they apply. "None" means no schema change. Current drift schema is 12 (`lib/data/db.dart:230`) and the latest migration is `010_intervals.sql`. A new one would be `011_*.sql` plus a `describe('011_…')` case in `supabase/migrations.test.ts` (pattern at lines 319-345).

| Feature | What Garmin / Strava does | Timburr possible? | What it needs | Claim status |
| --- | --- | --- | --- | --- |
| Per-step table (type, time, distance, pace) | Garmin Intervals tab; Strava lap list | **yes** (mostly exists) | Already shown as "Reps" (`interval_plans.dart:738-750`). Add a column layout and tenths if wanted. No schema. | verified [repo], high |
| Work vs recovery labels | Garmin: the step's *type* from the workout (here everything "Run"); Strava: the lap's *pace zone name* | **yes**, and better than Garmin here: Timburr's kinds are rep/recovery/warmup/cooldown from the plan | Exists (`stepLabel`, `intervals.dart:190`). No schema. | verified [repo] + [frame], high |
| Warm-up / cool-down rows | Garmin unnumbered warm-up row; Strava lap 1 | **yes** | Exists in StepMark kinds; a free run's trailing recovery becomes cool-down (`recorder.dart:443-446`). | verified, high |
| Filter by step type + **Total row per type** | Garmin chips All/Warm-up/Run, with a Total row; Stats "Run time / distance / pace" | **yes**, existing data | Generalise `summarizeReps` (`intervals.dart:299`) to any kind: sum sec / sum meters per kind, plus avg HR per kind via `stepAvgHr`. Pure function + flutter_test. No schema. | verified, high |
| Repeat grouping (round headers, per-round totals) | Neither app groups in the frames; Garmin lists steps flat | **yes**, existing data | Match StepMarks to `IntervalPlan.steps` the way `lastTimes` does (`intervals.dart:217-243`), then group by `PlanRepeat`. A free run has no plan: show flat. Optionally store the plan step id in StepMark (JSON only, no migration). | verified [repo], medium (matching edge cases) |
| Target vs actual pace per step | Garmin execution score (proprietary); targets shown on the watch | **yes** (a plain comparison, not Garmin's score) | `PlanStep.pace` exists (`intervals.dart:64-70`). Show actual − target, colour by on/over/under. No schema. | verified, high |
| Workout execution score (%) | Garmin, proprietary weighting | **no** (copying it); a simple "% of reps within ±N s of target" is possible | Own formula, labelled as Timburr's. | [official] manual for Garmin's rules; own formula unverified |
| Lap bar chart (width = duration, height = pace, colour = intensity) | Strava Laps screen | **yes**, existing data | Bars from StepMarks (startSec/endSec, pace), colour by kind (rep dark, recovery pale) or by pace zone. `fl_chart` BarChart spaces bars evenly, so true duration-width bars probably need a small `CustomPainter`, or LineChart step areas [unverified, medium]. No new package. No schema. | data verified; chart approach unverified, medium |
| Tap a bar: "Lap 2 · 8:22/km · Zone 1 · Recovery" header | Strava | **yes** for "Step · pace · kind"; **yes with new data** for "Zone N" | Kind is free. Pace zones need zone bounds: either derive from `predictor.dart` race predictions with no storage (like Strava's estimate), or add `settings.threshold_pace_sec` → drift schema 13 + `011_pace_zones.sql` + test case. Zone formula: own choice; Strava's numeric bounds are not published in the pages read. | zones: [official] names; bounds unverified |
| Pace / HR / elevation chart with step shading | Garmin pace chart (time axis); Strava pace + grey elevation | **yes** | The chart exists over distance (`run_page.dart:241`). Add a time-axis option, shade rep spans from StepMarks (`LineChartData.rangeAnnotations` in fl_chart [unverified, medium]), overlay elevation. No schema. | verified [repo] for the chart; annotation API unverified |
| Km splits with pace bar and elevation | Strava Splits (bar + Elev per km) | **yes** | `splitsPerKm` exists; add elevation difference per split from the smoothed altitude, plus a bar widget. No schema. | verified, high |
| Summary stats (distance, pace, moving time, elev gain, calories, HR) | Both | **yes** (exists) | `run_page.dart:117-132`. | verified, high |
| Avg cadence | Strava 161 spm; Garmin 158 | **yes with new data** | No cadence source on live runs. Options: read Health Connect `StepsCadenceRecord` or `StepsRecord` for the session, if the Fitbit writes them [unverified, low-medium], or phone step sensor. No SQL: the `cad` column and `avg_cadence` already exist (`006_runs.sql`). | gap verified [repo]; source unverified |
| HR zones (time in zone, per step HR) | Garmin zone bars; Strava HR zones | **yes** when HR was recorded; **no** without HR | ZoneBar + `stepAvgHr` exist. Zone time per step is a small pure function. | verified, high |
| Run / walk time | Garmin (accelerometer, `rwdRun`/`rwdWalk` splits) | **yes, approximate** | Classify by GPS speed (e.g. below about 7 km/h = walk) from the track. Not the same as Garmin's sensor method. | approximation unverified, medium |
| Grade-adjusted pace | Garmin GAP; Strava uses GAP for pace zones | **yes with work** | Needs a published GAP model (not researched here) + altitude, which exists. No schema. | unverified, medium |
| Elevation profile, +/− | Both | **yes** | Altitude stored; gain exists (`run_analysis.dart:79`). Add descent and min/max. No schema. | verified, high |
| Training Effect, training load (Firstbeat), stamina, Body Battery, recovery HR, sweat loss | Garmin proprietary | **no** | Proprietary algorithms and watch data. Timburr's Relative Effort is its own. | general knowledge, high |
| Power, power zones, running dynamics (GCT, vertical oscillation/ratio, stride) | Garmin from watch/HRM sensors | **no** | No sensor: the Fitbit Air shares HR only (design.md). Stride would need cadence (see above). | verified [repo/design], high |
| Athlete Intelligence text | Strava AI summary (subscriber) | **no** (offline app, no LLM in scope) | n/a | unverified, high |
| 3D satellite flyover replay | Strava | **no** as 3D satellite; **yes** as a 2D replay | 3D needs a 3D map SDK with satellite imagery, keys and a network dependency: out of scope. A 2D marker animated along the OSM route with a live pace/elev/distance header uses existing flutter_map + track. No schema. | 3D: unverified, high; 2D: verified data |
| Import a Garmin/Strava interval run with its steps | Strava reads FIT laps + `intensity`/`wkt_step_index` | **yes with new code** | TCX: keep `<Lap>` start/time/distance as StepMarks or laps (`strava_tcx.dart:23-39`); TCX laps carry `Intensity` Active/Resting [unverified, medium]. FIT: needs a Dart FIT parser package (none in pubspec), then map `lap.intensity` → StepKind. Track JSON only, no migration. | importer gap verified; formats partly unverified |

## 5. Recommended build order

1. **Per-kind totals** (pure, with tests): extend `summarizeReps` into a per-kind summary of time, distance, pace and avg HR. Show it at the top of the Steps section as "Reps: 8 · 2.3 km · 4:41 /km · 172 bpm" and "Recovery: …". This is Garmin's Total row and Stats "Run" totals. No schema.
2. **Steps table polish**: columns (#, kind, time, distance, pace, HR), a kind filter, rep vs recovery styling, and target vs actual pace when the plan step had a target.
3. **Interval bar chart**: duration-wide, pace-tall bars from StepMarks, coloured by kind, with tap-to-select showing "Rep 3 · 4:36 /km · 172 bpm". Above it, the existing pace chart with rep spans shaded.
4. **Repeat grouping** for planned runs, by matching steps to the plan copy (reuse the `lastTimes` matching).
5. **Splits elevation + bars**, and descent/min/max elevation.
6. *Optional, needs a decision:* **pace zones**. Derive them from race predictions (no storage) or add a threshold-pace setting (drift 13 + `011` migration + test). Then "Zone N" labels and zone colouring.
7. *Optional:* keep laps from TCX imports as steps. A cadence source. A 2D replay.

Not worth attempting: Training Effect, stamina, Body Battery, power/running dynamics, Athlete Intelligence, the 3D satellite flyover.

## Sources

- Garmin FIT Activity file: https://developer.garmin.com/fit/articles/file-types/activity.html
- Garmin FIT profile (lap, split, `intensity`, `lapTrigger`, `splitType`): https://github.com/garmin/fit-javascript-sdk/blob/main/src/profile.js
- Strava API reference (Lap, Split, DetailedActivity, StreamSet): https://developers.strava.com/docs/reference/
- Strava Mobile Workout Analysis: https://support.strava.com/hc/en-us/articles/115001136770-Mobile-Workout-Analysis
- Strava Training Zones: https://support.strava.com/hc/en-us/articles/39113532401421-Training-Zones-on-Strava
- Garmin fenix 8 manual, workout execution score: https://www8.garmin.com/manuals-apac/webhelp/fenix8series/EN-SG/GUID-F9FAB659-F4F4-47AF-AFB9-0FD8EC2B057B-9736.html
- Garmin forum, steps classified as Run: https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/293747/coach-workouts-warm-up-and-cool-down-steps-broken
