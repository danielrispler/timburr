-- Shoes, and the pair a Run was worn on. A retired pair keeps its Runs; its distance is the sum of them.

create table public.shoes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  is_default boolean not null default false, -- new Runs get this pair
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create trigger touch_row before insert or update on public.shoes for each row execute function public.touch_row();
create index on public.shoes (user_id, server_updated_at);

alter table public.shoes enable row level security;
create policy own_rows on public.shoes for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.shoes from anon;
grant select, insert, update, delete on public.shoes to authenticated;

alter table public.cardio add column shoe_id uuid references public.shoes on delete set null;
create index on public.cardio (shoe_id) where shoe_id is not null; -- an FK is not indexed by itself
