-- Drop sets, one backup exercise per slot, and Google Health stats on strength workouts.

alter table public.sets add column is_drop boolean not null default false;

alter table public.routine_exercises add column backup_exercise_id uuid references public.exercises;
-- Swapping in a workout exchanges exercise_id and backup_exercise_id.
alter table public.workout_exercises add column backup_exercise_id uuid references public.exercises;

alter table public.workouts
  add column avg_hr int check (avg_hr > 0),
  add column calories int check (calories >= 0),
  add column active_sec int check (active_sec >= 0),
  add column effort smallint check (effort between 1 and 10),
  add column cardio_load int check (cardio_load >= 0);
