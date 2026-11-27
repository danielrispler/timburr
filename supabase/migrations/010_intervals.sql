-- Interval runs and their saved plans. Treadmill Runs are no longer made (Daniel runs only outside); the type stays valid so old rows and backups load.

alter table public.cardio drop constraint cardio_type_check;
alter table public.cardio add constraint cardio_type_check
  check (type in ('run', 'interval', 'walk', 'treadmill', 'bike', 'swim', 'padel', 'tennis', 'soccer', 'basketball'));

-- A saved, named structure for an Interval run (lib/data/intervals.dart, IntervalPlan.toJson): warm-up, reps x (rep + recovery), cool-down.
create table public.interval_plans (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  structure jsonb not null check (jsonb_typeof(structure) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create trigger touch_row before insert or update on public.interval_plans for each row execute function public.touch_row();
create index on public.interval_plans (user_id, server_updated_at);

alter table public.interval_plans enable row level security;
create policy own_rows on public.interval_plans for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.interval_plans from anon;
grant select, insert, update, delete on public.interval_plans to authenticated;

-- The plan an Interval run was run to, and a copy of it as it was then (a plan can be edited or deleted later). Both null on a free Interval run.
alter table public.cardio add column interval_plan_id uuid references public.interval_plans on delete set null;
alter table public.cardio add column interval_plan jsonb check (jsonb_typeof(interval_plan) = 'object');
create index on public.cardio (interval_plan_id) where interval_plan_id is not null; -- an FK is not indexed by itself
