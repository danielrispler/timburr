-- Run data: extra cardio columns, one synced track per Run, and a single settings row.
-- duration_sec stays Moving time. Other cardio types stay valid so old backups restore.

alter table public.cardio
  add column elapsed_sec int check (elapsed_sec > 0),
  add column title text,
  add column source text check (source in ('manual', 'file', 'health_connect', 'recorded')),
  add column external_id text,
  add column elevation_gain_m numeric(7, 1) check (elevation_gain_m >= 0),
  add column max_hr int check (max_hr > 0),
  add column avg_cadence numeric(5, 1) check (avg_cadence >= 0),
  add column calories int check (calories >= 0),
  add column route text, -- simplified polyline of about 200 points, for map thumbnails
  add column edited_fields text[] not null default '{}'; -- fields Daniel edited; a merge never replaces them

create table public.cardio_tracks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  cardio_id uuid not null unique references public.cardio on delete cascade,
  points text not null, -- gzip + base64 of column arrays (time, distance, lat, lon, altitude, HR, cadence)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- One row per user, with a fixed id chosen by the client.
create table public.settings (
  id uuid primary key,
  user_id uuid not null unique default auth.uid() references auth.users on delete cascade,
  max_hr int check (max_hr between 100 and 250),
  birth_year int check (birth_year between 1900 and 2100),
  stride_m numeric(4, 3) check (stride_m > 0), -- treadmill stride length
  stride_samples int check (stride_samples >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

do $$
declare
  t text;
begin
  foreach t in array array['cardio_tracks', 'settings'] loop
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
