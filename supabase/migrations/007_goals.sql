-- Weekly and yearly distance goals: one row per user, with a fixed id chosen by the client.
-- A null goal means "not set".

create table public.goals (
  id uuid primary key,
  user_id uuid not null unique default auth.uid() references auth.users on delete cascade,
  weekly_km numeric(6, 1) check (weekly_km > 0),
  yearly_km numeric(7, 1) check (yearly_km > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create trigger touch_row before insert or update on public.goals for each row execute function public.touch_row();
create index on public.goals (user_id, server_updated_at);

alter table public.goals enable row level security;
create policy own_rows on public.goals for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.goals from anon;
grant select, insert, update, delete on public.goals to authenticated;
