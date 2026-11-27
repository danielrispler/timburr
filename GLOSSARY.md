# Glossary

**Workout**: one gym session of exercises and sets. Together with Runs, these are the only activities Timburr records.

**Saved workout**: a reusable plan of exercises a Workout can start from.
_Avoid_: routine (in the UI), template

**Superset**: two or more exercises done back to back as one block. Their sets alternate (A1, B1, A2, B2). Rest comes only after the last exercise of each round.

**Round**: one set of every exercise in a superset, taken in order.

**Drop set**: a set done right after the set before it, at a lower weight and with no rest between. It belongs to that set.

**Alternative**: one of the exercises a routine slot can hold, in order; the first is the default. Daniel can swap to any of them during a workout, or to any other exercise, which then joins the slot as an alternative. The exercise he actually does is the one recorded. Swapping never changes the default.
_Avoid_: backup exercise

**Machine**: a specific piece of equipment, such as the upstairs leg extension. It is not its own exercise: doing an exercise on another machine is the same exercise, with the machine written in that day's note. Its PRs and history mix machines.

**Skipped exercise**: an exercise in a workout that Daniel didn't do that day. None of its sets count, and skipping it never changes the routine.

**Health stats**: the numbers Google Health records for a strength workout: average heart rate, calories, duration, effort (1-10) and cardio load. They are optional. Heart rate, calories and duration fill in from an overlapping Fitbit session; what Daniel typed is never replaced.

## Running

**Run**: an outdoor run. Daniel runs only outside, so Timburr has no treadmill runs. Runs count toward running distance, time, weekly totals and goals. A Run exists only because Daniel recorded it, imported a file or typed it in. Recordings whose times overlap are one Run, wherever they came from.
_Avoid_: cardio, activity

**Interval run**: a Run made of fast reps and easy recoveries, either guided by an Interval plan or switched by hand (a free Interval run). It counts like any other Run and keeps a copy of the plan name and steps it ran. A Run without intervals is just a Run.
_Avoid_: speed work, workout

**Interval plan**: a saved, named structure for an Interval run: an optional warm-up, a number of reps each followed by a recovery, and an optional cool-down.

**Plan history**: every Interval run done with one Interval plan, newest first, compared by average rep pace and fastest rep. Editing the plan keeps its history. Deleting the plan removes its history, but not its Runs.

**Step**: one part of an Interval plan: a warm-up, rep, recovery or cool-down. Each step is a distance or a time. A time step follows the clock, so standing still during a recovery doesn't make it longer.

**Rep**: a fast step of an Interval run.
_Avoid_: interval, lap, split

**Recovery**: the easy step after a rep.
_Avoid_: rest

**Auto-detected run**: a running session the Fitbit noticed by itself, starting 10 to 20 minutes late and without a route. It never becomes a Run on its own: it only fills in the Run it overlaps.

**Run/walk**: a Run with walking breaks. It is a Run with a note, not its own type.

**Moving time**: the time spent moving during a Run, with pauses removed. A Run's duration and pace always mean moving time.
_Avoid_: active time

**Elapsed time**: the clock time from a Run's start to its end, pauses included.

**Best effort**: the fastest time for a standard distance (400 m, 1 km, 1 mile, 5 km, 10 km, half marathon) within any part of one Run.

**PR**: the best result ever. For a Run distance, it's the fastest best effort. For an exercise, it's the heaviest weight, best estimated 1RM, best session volume, most reps or longest time.
_Avoid_: personal best, record

**Max HR**: the highest heart rate Daniel can reach. HR zones are set from it.

**HR zone**: one of five equal bands of Max HR, from 50% to 100%. Zone 1 is the easiest.

**Recording**: what Daniel captures live with the phone: GPS for a Run, plus the heart rate band when connected. It is saved as it goes, and finishing it makes a Run. The same word covers what any source (file, Health Connect, live) hands to the Run store.

**Lap**: a stretch of a Run between two presses of the Lap button (the first starts at the start, the last ends with the Run). A lap shows time and distance. An Interval run has reps instead of laps.

**HR band**: the Bluetooth heart rate band (the Fitbit Air) that streams live heart rate during a Recording. Daniel chooses it once on the recording setup screen and it is remembered; a Recording never picks one on its own.

**Relative Effort**: how hard a Run was. Minutes in each HR zone times the zone number, summed, so an hour in zone 2 counts 120. A Run with no heart rate counts its Moving time as zone 2 and shows no Relative Effort.

**Fitness / Fatigue / Form**: the training-load curves on Progress, from each day's Relative Effort. Fitness is the 42-day average, Fatigue the 7-day average, and Form is Fitness minus Fatigue: negative when tired, positive when fresh.

**Matched route**: Runs over the same outdoor route, in the same direction and about the same length. Timburr groups them from the stored route, and the group page charts Moving time on it.

**Shoe**: a pair of running shoes. Each Run belongs to at most one, and new Runs get the default pair. A pair's distance is the sum of its Runs. Retiring a pair keeps its Runs.

**Goal**: a weekly or yearly distance target for Runs. Either can be left unset.
