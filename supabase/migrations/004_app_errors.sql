-- Errors the app caught, pushed after each sync. Check `select * from app_errors order by last_at desc` for new ones.
-- Push only: the app never pulls this table, and deletes its local copy once pushed.

create table public.app_errors (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  source text not null,                -- flutter, platform, sync, backup, import, health_ocr
  error_type text not null,            -- runtimeType of the error
  message text not null,
  stack text,
  context jsonb not null default '{}', -- extra details from the catch site
  count int not null default 1 check (count > 0), -- identical errors folded into one row
  first_at timestamptz not null,
  last_at timestamptz not null,
  app_version text,
  os text,
  received_at timestamptz not null default now()
);

create index app_errors_last_at on public.app_errors (last_at desc);

alter table public.app_errors enable row level security;
create policy own_rows on public.app_errors for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.app_errors from anon;
grant select, insert, update, delete on public.app_errors to authenticated;
