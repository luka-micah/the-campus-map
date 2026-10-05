-- BOUESTI Campus Map — initial schema
-- Paste this whole file into Supabase Dashboard > SQL Editor > New Query > Run.
-- It matches lib/core/models/*.dart (LocationModel, EdgeModel, UserProfile)
-- and lib/data/supabase_service.dart expectations.
--
-- Order: tables -> indexes -> RLS + policies -> grants -> realtime

-- Required for gen_random_uuid() on older projects (no-op if already enabled).
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  department text not null default '',
  lat double precision not null,
  lng double precision not null,
  hours text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.edges (
  id uuid primary key default gen_random_uuid(),
  from_location_id uuid not null references public.locations(id) on delete cascade,
  to_location_id uuid not null references public.locations(id) on delete cascade,
  distance_meters double precision not null check (distance_meters > 0),
  check (from_location_id <> to_location_id)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  is_admin boolean not null default false
);

-- ---------------------------------------------------------------------------
-- 2. Indexes
-- ---------------------------------------------------------------------------

create index if not exists edges_from_idx on public.edges(from_location_id);
create index if not exists edges_to_idx on public.edges(to_location_id);
create index if not exists locations_name_idx on public.locations(name);

-- ---------------------------------------------------------------------------
-- 3. Row Level Security + policies
-- ---------------------------------------------------------------------------

alter table public.locations enable row level security;
alter table public.edges enable row level security;
alter table public.profiles enable row level security;

-- Drop existing policies so this file is re-runnable (both the legacy
-- permissive names and the admin-gated names below).
drop policy if exists "public read locations" on public.locations;
drop policy if exists "public read edges" on public.edges;
drop policy if exists "auth write locations" on public.locations;
drop policy if exists "auth write edges" on public.edges;
drop policy if exists "admin write locations" on public.locations;
drop policy if exists "admin write edges" on public.edges;
drop policy if exists "auth read profiles" on public.profiles;
drop policy if exists "users insert own profile" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;

-- Map must be readable before login and by realtime streams.
create policy "public read locations"
on public.locations for select to anon, authenticated using (true);

create policy "public read edges"
on public.edges for select to anon, authenticated using (true);

-- Requirement 10.6: writes are admin-only. Any direct INSERT/UPDATE/DELETE
-- on locations/edges by a non-admin (authenticated or anon) is rejected by
-- RLS with a permission error. The app performs admin writes as the logged-in
-- admin user, which satisfies the is_admin check.
create policy "admin write locations"
on public.locations for all to authenticated
using (exists (
  select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
))
with check (exists (
  select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
));

create policy "admin write edges"
on public.edges for all to authenticated
using (exists (
  select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
))
with check (exists (
  select 1 from public.profiles p where p.id = auth.uid() and p.is_admin
));

-- AuthService.getProfiles() reads all profiles after login, and register
-- inserts exactly one row with id = auth.uid().
create policy "auth read profiles"
on public.profiles for select to authenticated using (true);

create policy "users insert own profile"
on public.profiles for insert to authenticated with check (auth.uid() = id);

create policy "users update own profile"
on public.profiles for update to authenticated using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 4. Grants (Data API needs these in addition to RLS)
-- ---------------------------------------------------------------------------

grant select on public.locations, public.edges to anon, authenticated;
grant insert, update, delete on public.locations, public.edges to authenticated;
grant select, insert, update on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Realtime (required for .stream(primaryKey: ['id']) in supabase_service.dart)
-- ---------------------------------------------------------------------------

-- Also enable in Dashboard > Database > Replication > supabase_realtime
-- and tick locations + edges if this block is skipped.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'locations'
  ) then
    alter publication supabase_realtime add table public.locations;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'edges'
  ) then
    alter publication supabase_realtime add table public.edges;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Optional test seed (uncomment to verify map + routing end-to-end)
-- ---------------------------------------------------------------------------
-- insert into public.locations (name, department, lat, lng, hours) values
--   ('Main Gate', 'Entrance', 7.0000, 3.9000, '06:00-22:00'),
--   ('Library', 'Academics', 7.0015, 3.9012, '08:00-20:00')
-- returning id;
-- -- Copy the two returned ids into from_location_id / to_location_id:
-- insert into public.edges (from_location_id, to_location_id, distance_meters) values
--   ('<MAIN_GATE_ID>', '<LIBRARY_ID>', 180);

-- ---------------------------------------------------------------------------
-- 7. Make your first admin (run after registering once via the app)
-- ---------------------------------------------------------------------------
-- update public.profiles set is_admin = true where username = 'your_username';
