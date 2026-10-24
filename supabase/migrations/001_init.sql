-- Timburr initial schema.
--
-- Every table has the same common columns:
--   id                 uuid generated on the client
--   user_id            owner; RLS only lets a user touch their own rows
--   created_at
--   updated_at         set by the client on every change; decides last-write-wins
--   deleted_at         soft delete, so deletions sync like any other change
--   server_updated_at  set by the touch_row trigger; the app pulls rows changed since its last pull by this column
--
-- The exercise library (free-exercise-db) is bundled in the app, never stored here.
-- A library exercise gets a row in `exercises` only once it is used or configured (sticky note, load type, rest).

create table public.exercises (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  library_id text,       -- free-exercise-db id; null for a custom exercise
  name text,             -- custom exercises only; library names come from the bundled dataset
  load_type text check (load_type in ('weighted', 'bodyweight', 'timed')), -- null on a library row = dataset default
  muscles text[] not null default '{}',
  equipment text,
  sticky_note text,
  last_rest_sec int check (last_rest_sec > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  check ((library_id is null) <> (name is null)),
  check (library_id is not null or load_type is not null),
  unique (user_id, library_id)
);

create table public.routines (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  sticky_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.routine_exercises (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  routine_id uuid not null references public.routines on delete cascade,
  exercise_id uuid not null references public.exercises,
  position int not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.workouts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  routine_id uuid references public.routines on delete set null,
  started_at timestamptz not null,
  finished_at timestamptz, -- null while the workout is in progress
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.workout_exercises (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  workout_id uuid not null references public.workouts on delete cascade,
  exercise_id uuid not null references public.exercises,
  position int not null,
  notes text,
  superset_with_next boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.sets (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  workout_exercise_id uuid not null references public.workout_exercises on delete cascade,
  set_number int not null,
  weight_kg numeric(6, 2), -- weighted: the load; bodyweight: added weight (null = none)
  reps int check (reps >= 0),
  duration_sec int check (duration_sec >= 0), -- timed exercises use this instead of reps
  done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.cardio (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  type text not null check (type in ('run', 'walk', 'treadmill', 'bike')),
  started_at timestamptz not null,
  distance_km numeric(6, 2) not null check (distance_km > 0),
  duration_sec int not null check (duration_sec > 0),
  avg_hr int check (avg_hr > 0),
  incline_pct numeric(4, 1),
  rpe smallint check (rpe between 1 and 10),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create index on public.routine_exercises (routine_id);
create index on public.workout_exercises (workout_id);
create index on public.sets (workout_exercise_id);

create function public.touch_row() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Last write wins: ignore an update older than the stored row (e.g. a late push from a second device).
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

-- Same trigger, RLS policy, pull index and grants on every table.
do $$
declare
  t text;
begin
  foreach t in array array['exercises', 'routines', 'routine_exercises', 'workouts', 'workout_exercises', 'sets', 'cardio'] loop
    execute format('create trigger touch_row before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (user_id, server_updated_at)', t);
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy own_rows on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      t
    );
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end;
$$;
