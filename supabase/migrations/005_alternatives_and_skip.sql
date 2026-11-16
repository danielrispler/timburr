-- Several alternatives per routine slot, and skipping an exercise for one workout.
-- alternative_ids replaces backup_exercise_id, which is kept but no longer written.

alter table public.routine_exercises add column alternative_ids uuid[] not null default '{}';
alter table public.workout_exercises
  add column alternative_ids uuid[] not null default '{}',
  -- Not done today: its sets count in no stats, and it stays in the routine.
  add column skipped boolean not null default false;

update public.routine_exercises set alternative_ids = array[backup_exercise_id] where backup_exercise_id is not null;
update public.workout_exercises set alternative_ids = array[backup_exercise_id] where backup_exercise_id is not null;
