-- MigrateOS CRM schema
-- Run this once in your Supabase project's SQL Editor (Database > SQL Editor > New query).

-- Staff profiles, one row per logged-in user, auto-created on signup.
create table if not exists profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  created_at timestamptz not null default now()
);

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- Leads / clients
create table if not exists contacts (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  email text,
  source text,               -- e.g. Instagram, WhatsApp, Referral, Walk-in
  service text,               -- e.g. Work Visa, Study Visa, Tourist Visa, Job Placement
  country text,                -- e.g. UAE, UK, Canada, Australia
  status text not null default 'inquiry'
    check (status in ('inquiry', 'documentation', 'filed', 'approved', 'rejected')),
  assigned_to uuid references profiles (id),
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists contacts_status_idx on contacts (status);
create index if not exists contacts_assigned_to_idx on contacts (assigned_to);

-- Notes on a contact
create table if not exists notes (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contacts (id) on delete cascade,
  body text not null,
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists notes_contact_id_idx on notes (contact_id);

-- Follow-up tasks on a contact
create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contacts (id) on delete cascade,
  title text not null,
  due_date date,
  done boolean not null default false,
  assigned_to uuid references profiles (id),
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists tasks_contact_id_idx on tasks (contact_id);
create index if not exists tasks_assigned_to_idx on tasks (assigned_to);
create index if not exists tasks_due_date_idx on tasks (due_date);

-- Row Level Security: any signed-in staff account can read/write.
-- There is no public/anon access at all — only authenticated users.
alter table profiles enable row level security;
alter table contacts enable row level security;
alter table notes enable row level security;
alter table tasks enable row level security;

drop policy if exists "staff read profiles" on profiles;
create policy "staff read profiles" on profiles for select
  using (auth.role() = 'authenticated');

drop policy if exists "staff all contacts" on contacts;
create policy "staff all contacts" on contacts for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

drop policy if exists "staff all notes" on notes;
create policy "staff all notes" on notes for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

drop policy if exists "staff all tasks" on tasks;
create policy "staff all tasks" on tasks for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- After running this:
-- 1. Authentication > Providers: make sure Email is enabled.
-- 2. Authentication > Settings: turn OFF "Allow new users to sign up" if you
--    only want staff you create by hand to have access.
-- 3. Authentication > Users > Add user, for each staff member.
