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
| cardio `type` | `run`, `walk`, `treadmill` or `bike`. |
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
