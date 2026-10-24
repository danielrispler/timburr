-- Planned sets per saved-workout exercise, and sports in cardio (no distance).

create table public.routine_sets (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  routine_exercise_id uuid not null references public.routine_exercises on delete cascade,
  set_number int not null,
  weight_kg numeric(6, 2), -- null = use last session's weight
  reps int check (reps >= 0),
  duration_sec int check (duration_sec >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create index on public.routine_sets (routine_exercise_id);
create trigger touch_row before insert or update on public.routine_sets for each row execute function public.touch_row();
create index on public.routine_sets (user_id, server_updated_at);
alter table public.routine_sets enable row level security;
create policy own_rows on public.routine_sets for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.routine_sets from anon;
grant select, insert, update, delete on public.routine_sets to authenticated;

alter table public.cardio drop constraint cardio_type_check;
alter table public.cardio add constraint cardio_type_check
  check (type in ('run', 'walk', 'treadmill', 'bike', 'swim', 'padel', 'tennis', 'soccer', 'basketball'));
alter table public.cardio alter column distance_km drop not null;
alter table public.cardio add constraint cardio_distance_check
  check (distance_km is not null or type in ('padel', 'tennis', 'soccer', 'basketball'));
