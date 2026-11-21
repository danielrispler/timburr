# Import format, version 1

More > Import accepts one JSON object. "Copy import format" copies a short version of this page plus your custom exercises and the exercises you have used, for pasting to a chat assistant with a screenshot.

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
          "sets": [{ "weightKg": 70, "reps": 10 }, { "weightKg": 80, "reps": 8 }]
        }
      ]
    }
  ],
  "cardio": [
    { "type": "run", "date": "2026-10-23T17:15", "distanceKm": 5.0, "durationSec": 1680,
      "avgHr": 158, "inclinePct": null, "rpe": 7, "notes": "" }
  ]
}
```

## Fields

| Field | Rule |
|---|---|
| `version` | Required, must be `1`. |
| `workouts`, `cardio` | Optional lists. |
| workout `date` | Required, ISO local time (`2026-10-24T16:13`). Saved as both start and finish time. |
| workout `routine` | Optional. Linked when it matches a routine name (any case), otherwise ignored. |
| `notes` | Optional text everywhere. Empty text is saved as no note. |
| workout `exercises` | Required, non-empty. |
| exercise `name` | Required. Matched case-insensitively against library and custom exercises. |
| exercise `supersetWithNext` | Optional `true`/`false`. |
| exercise `sets` | Required, non-empty. |
| set `weightKg` | Optional number >= 0. For bodyweight sets it is the added weight, or `null`. |
| set `reps` / `durationSec` | Exactly one, a whole number >= 0. Timed sets use `durationSec`. |
| cardio `type` | `run` or `treadmill`. Other types (walk, bike, swim, sports) are rejected. |
| cardio `date` | Required, as for workouts. |
| cardio `distanceKm` | Required number > 0. |
| cardio `durationSec` | Required whole number > 0. |
| cardio `avgHr` | Optional whole number > 0. |
| cardio `inclinePct` | Optional number. |
| cardio `rpe` | Optional whole number 1-10. |

Any other field is an error. Errors are listed per field (for example `workouts[0].exercises[1].sets[2].reps: must be a whole number >= 0`), and nothing is saved until all are fixed.

## Unknown exercises

Each name with no match is shown before saving. Tap it to map it to an existing exercise; otherwise it becomes a new custom exercise. Its load type is `timed` if any set has `durationSec`, `bodyweight` if no set has a weight, else `weighted`.

## Saving

Everything is saved in one transaction: either all workouts and cardio are stored, or none. Imported sets are marked done, so they count toward PRs and "Last time".

## Export

More > Backup / Restore > Export workouts writes this format, so an export can be imported back. Pick Today, This week (Monday to Sunday), Pick dates… (both ends included) or All workouts. It shares `timburr-workouts-<range>.json`, for example `timburr-workouts-2026-11-16-to-2026-11-22.json`. It is not a backup, so the backup reminder is not reset.

- Finished workouts and cardio started in the range, oldest first. Unfinished and deleted ones are left out.
- Dates are local time, `2026-10-24T16:13`. Exercise names are the library or custom names. `routine` is the linked routine's name.
- Empty optional fields are left out. `supersetWithNext` is always written.
- The format has no way to show these, so they are left out: skipped exercises, drop sets, sets not ticked done, and sets with neither reps nor time. An exercise with no sets left, and a workout with no exercises left, is left out too.
- Workout duration, Google Health stats and routine plans are not exported. Use Export backup for everything.
