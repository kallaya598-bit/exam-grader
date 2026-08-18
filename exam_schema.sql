-- ============================================================
-- Exam Grader — multi-school schema for Supabase Auth
-- Run once in the dedicated exam-grader Supabase project.
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.exam_schools (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code        text not null unique,
  logo_url    text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.exam_profiles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  school_id   uuid not null references public.exam_schools(id) on delete cascade,
  email       text not null,
  full_name   text not null,
  role        text not null default 'teacher' check (role in ('admin', 'teacher')),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (school_id, email)
);

-- Platform owners can create schools and invite the first school admin.
create table if not exists public.exam_platform_admins (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists public.exam_subjects (
  id                bigint generated always as identity primary key,
  school_id         uuid not null references public.exam_schools(id) on delete cascade,
  created_by        uuid not null default auth.uid() references auth.users(id),
  subject_name      text not null,
  class_level       text,
  room              text,
  exam_title        text,
  school_name       text,
  num_questions     int not null default 20 check (num_questions between 1 and 60),
  choices           int not null default 4 check (choices in (4, 5)),
  answer_key        jsonb not null default '{}'::jsonb,
  question_scores   jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (id, school_id)
);

create table if not exists public.exam_results (
  id            bigint generated always as identity primary key,
  school_id     uuid not null references public.exam_schools(id) on delete cascade,
  subject_id    bigint not null,
  graded_by     uuid not null default auth.uid() references auth.users(id),
  student_name  text,
  student_no    text,
  room          text,
  score         numeric,
  total         numeric,
  percent       numeric,
  answers       jsonb,
  graded_at     timestamptz not null default now(),
  constraint exam_results_subject_school_fk
    foreign key (subject_id, school_id)
    references public.exam_subjects(id, school_id)
    on delete cascade
);

create index if not exists idx_exam_profiles_school on public.exam_profiles(school_id);
create index if not exists idx_exam_subjects_school on public.exam_subjects(school_id);
create index if not exists idx_exam_subjects_updated on public.exam_subjects(school_id, updated_at desc);
create index if not exists idx_exam_results_school on public.exam_results(school_id);
create index if not exists idx_exam_results_subject on public.exam_results(subject_id);

create or replace function public.exam_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists exam_schools_set_updated_at on public.exam_schools;
create trigger exam_schools_set_updated_at
  before update on public.exam_schools
  for each row execute function public.exam_set_updated_at();

drop trigger if exists exam_profiles_set_updated_at on public.exam_profiles;
create trigger exam_profiles_set_updated_at
  before update on public.exam_profiles
  for each row execute function public.exam_set_updated_at();

drop trigger if exists exam_subjects_set_updated_at on public.exam_subjects;
create trigger exam_subjects_set_updated_at
  before update on public.exam_subjects
  for each row execute function public.exam_set_updated_at();

create or replace function public.exam_current_school_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select school_id
  from public.exam_profiles
  where user_id = auth.uid() and active = true
  limit 1
$$;

create or replace function public.exam_is_school_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.exam_profiles
    where user_id = auth.uid() and active = true and role = 'admin'
  )
$$;

create or replace function public.exam_is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.exam_platform_admins where user_id = auth.uid()
  )
$$;

revoke all on function public.exam_current_school_id() from public;
revoke all on function public.exam_is_school_admin() from public;
revoke all on function public.exam_is_platform_admin() from public;
grant execute on function public.exam_current_school_id() to authenticated;
grant execute on function public.exam_is_school_admin() to authenticated;
grant execute on function public.exam_is_platform_admin() to authenticated;

alter table public.exam_schools enable row level security;
alter table public.exam_profiles enable row level security;
alter table public.exam_platform_admins enable row level security;
alter table public.exam_subjects enable row level security;
alter table public.exam_results enable row level security;

drop policy if exists exam_schools_select_own on public.exam_schools;
create policy exam_schools_select_own on public.exam_schools
  for select to authenticated
  using (id = public.exam_current_school_id() or public.exam_is_platform_admin());

drop policy if exists exam_schools_platform_insert on public.exam_schools;
create policy exam_schools_platform_insert on public.exam_schools
  for insert to authenticated
  with check (public.exam_is_platform_admin());

drop policy if exists exam_schools_admin_update on public.exam_schools;
create policy exam_schools_admin_update on public.exam_schools
  for update to authenticated
  using (
    (id = public.exam_current_school_id() and public.exam_is_school_admin())
    or public.exam_is_platform_admin()
  )
  with check (
    (id = public.exam_current_school_id() and public.exam_is_school_admin())
    or public.exam_is_platform_admin()
  );

drop policy if exists exam_schools_platform_delete on public.exam_schools;
create policy exam_schools_platform_delete on public.exam_schools
  for delete to authenticated
  using (public.exam_is_platform_admin());

drop policy if exists exam_platform_admins_select_self on public.exam_platform_admins;
create policy exam_platform_admins_select_self on public.exam_platform_admins
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists exam_profiles_select_school on public.exam_profiles;
create policy exam_profiles_select_school on public.exam_profiles
  for select to authenticated
  using (school_id = public.exam_current_school_id() or public.exam_is_platform_admin());

drop policy if exists exam_profiles_admin_insert on public.exam_profiles;
create policy exam_profiles_admin_insert on public.exam_profiles
  for insert to authenticated
  with check (
    (school_id = public.exam_current_school_id() and public.exam_is_school_admin())
    or public.exam_is_platform_admin()
  );

drop policy if exists exam_profiles_admin_update on public.exam_profiles;
create policy exam_profiles_admin_update on public.exam_profiles
  for update to authenticated
  using (
    (school_id = public.exam_current_school_id() and public.exam_is_school_admin())
    or public.exam_is_platform_admin()
  )
  with check (
    (school_id = public.exam_current_school_id() and public.exam_is_school_admin())
    or public.exam_is_platform_admin()
  );

drop policy if exists exam_profiles_admin_delete on public.exam_profiles;
create policy exam_profiles_admin_delete on public.exam_profiles
  for delete to authenticated
  using (
    (
      school_id = public.exam_current_school_id()
      and public.exam_is_school_admin()
      and user_id <> auth.uid()
    )
    or public.exam_is_platform_admin()
  );

drop policy if exists exam_subjects_select_school on public.exam_subjects;
create policy exam_subjects_select_school on public.exam_subjects
  for select to authenticated
  using (school_id = public.exam_current_school_id());

drop policy if exists exam_subjects_insert_school on public.exam_subjects;
create policy exam_subjects_insert_school on public.exam_subjects
  for insert to authenticated
  with check (school_id = public.exam_current_school_id() and created_by = auth.uid());

drop policy if exists exam_subjects_update_school on public.exam_subjects;
create policy exam_subjects_update_school on public.exam_subjects
  for update to authenticated
  using (school_id = public.exam_current_school_id())
  with check (school_id = public.exam_current_school_id());

drop policy if exists exam_subjects_delete_school on public.exam_subjects;
create policy exam_subjects_delete_school on public.exam_subjects
  for delete to authenticated
  using (school_id = public.exam_current_school_id());

drop policy if exists exam_results_select_school on public.exam_results;
create policy exam_results_select_school on public.exam_results
  for select to authenticated
  using (school_id = public.exam_current_school_id());

drop policy if exists exam_results_insert_school on public.exam_results;
create policy exam_results_insert_school on public.exam_results
  for insert to authenticated
  with check (school_id = public.exam_current_school_id() and graded_by = auth.uid());

drop policy if exists exam_results_update_school on public.exam_results;
create policy exam_results_update_school on public.exam_results
  for update to authenticated
  using (school_id = public.exam_current_school_id())
  with check (school_id = public.exam_current_school_id());

drop policy if exists exam_results_delete_school on public.exam_results;
create policy exam_results_delete_school on public.exam_results
  for delete to authenticated
  using (school_id = public.exam_current_school_id());

revoke all on table public.exam_schools from anon;
revoke all on table public.exam_profiles from anon;
revoke all on table public.exam_platform_admins from anon;
revoke all on table public.exam_subjects from anon;
revoke all on table public.exam_results from anon;

grant select, update on table public.exam_schools to authenticated;
grant select, insert, update, delete on table public.exam_profiles to authenticated;
grant select on table public.exam_platform_admins to authenticated;
grant select, insert, update, delete on table public.exam_subjects to authenticated;
grant select, insert, update, delete on table public.exam_results to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Edge Functions use the service_role client for trusted invitation writes.
-- Grant it explicitly because tables created through the SQL editor may not
-- inherit the dashboard's usual service-role privileges.
grant usage on schema public to service_role;
grant all privileges on table public.exam_schools to service_role;
grant all privileges on table public.exam_profiles to service_role;
grant all privileges on table public.exam_platform_admins to service_role;
grant all privileges on table public.exam_subjects to service_role;
grant all privileges on table public.exam_results to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Create the first Auth user before inserting the first school and admin profile.
