create extension if not exists pgcrypto;

create type public.app_role as enum (
  'administrator',
  'secondary_subject_teacher',
  'secondary_class_teacher',
  'primary_teacher',
  'nursery_teacher'
);

create type public.school_stage as enum ('secondary', 'primary', 'nursery');
create type public.result_status as enum ('draft', 'submitted', 'under_review', 'approved', 'locked');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 160),
  role public.app_role not null,
  is_active boolean not null default true,
  must_change_password boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 80),
  stage public.school_stage not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (name, stage)
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) between 1 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.academic_sessions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) between 4 and 20),
  starts_on date not null,
  ends_on date not null,
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  check (starts_on < ends_on)
);

create unique index academic_sessions_one_current
  on public.academic_sessions (is_current)
  where is_current;

create table public.terms (
  id uuid primary key default gen_random_uuid(),
  academic_session_id uuid not null references public.academic_sessions (id) on delete restrict,
  term_number smallint not null check (term_number between 1 and 3),
  name text not null check (length(trim(name)) between 1 and 40),
  starts_on date,
  ends_on date,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (academic_session_id, term_number),
  unique (id, academic_session_id),
  check (starts_on is null or ends_on is null or starts_on < ends_on)
);

create unique index terms_one_active_per_session
  on public.terms (academic_session_id)
  where is_active;

create table public.students (
  id uuid primary key default gen_random_uuid(),
  admission_number text not null unique check (length(trim(admission_number)) between 1 and 40),
  first_name text not null check (length(trim(first_name)) between 1 and 80),
  last_name text not null check (length(trim(last_name)) between 1 and 80),
  other_names text,
  gender text check (gender in ('female', 'male', 'other', 'undisclosed')),
  date_of_birth date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.class_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete restrict,
  class_id uuid not null references public.classes (id) on delete restrict,
  academic_session_id uuid not null references public.academic_sessions (id) on delete restrict,
  enrolled_on date not null default current_date,
  left_on date,
  created_at timestamptz not null default now(),
  unique (student_id, academic_session_id),
  unique (student_id, class_id, academic_session_id),
  check (left_on is null or enrolled_on <= left_on)
);

create table public.class_teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles (id) on delete restrict,
  class_id uuid not null references public.classes (id) on delete restrict,
  academic_session_id uuid not null references public.academic_sessions (id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (teacher_id, class_id, academic_session_id),
  unique (class_id, academic_session_id)
);

create table public.class_subject_offerings (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes (id) on delete restrict,
  subject_id uuid not null references public.subjects (id) on delete restrict,
  academic_session_id uuid not null references public.academic_sessions (id) on delete restrict,
  counts_toward_average boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (class_id, subject_id, academic_session_id),
  unique (id, class_id, academic_session_id)
);

create table public.subject_teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles (id) on delete restrict,
  class_subject_offering_id uuid not null references public.class_subject_offerings (id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (teacher_id, class_subject_offering_id)
);

create table public.user_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  permission_key text not null check (permission_key in ('results.read', 'results.edit', 'register.manage')),
  class_id uuid references public.classes (id) on delete cascade,
  subject_id uuid references public.subjects (id) on delete cascade,
  academic_session_id uuid references public.academic_sessions (id) on delete cascade,
  allowed boolean not null,
  granted_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  check (subject_id is null or class_id is not null)
);

create unique index user_permission_overrides_scope
  on public.user_permission_overrides (
    user_id,
    permission_key,
    coalesce(class_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(subject_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(academic_session_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table public.assessment_schemes (
  id uuid primary key default gen_random_uuid(),
  class_subject_offering_id uuid not null unique references public.class_subject_offerings (id) on delete restrict,
  name text not null default 'Default assessment',
  created_at timestamptz not null default now(),
  unique (id, class_subject_offering_id)
);

create table public.assessment_components (
  id uuid primary key default gen_random_uuid(),
  assessment_scheme_id uuid not null references public.assessment_schemes (id) on delete restrict,
  code text not null check (length(trim(code)) between 1 and 40),
  name text not null check (length(trim(name)) between 1 and 80),
  max_score numeric(7, 2) not null check (max_score > 0),
  display_order smallint not null check (display_order > 0),
  counts_toward_total boolean not null default true,
  created_at timestamptz not null default now(),
  unique (assessment_scheme_id, code),
  unique (assessment_scheme_id, display_order),
  unique (id, assessment_scheme_id)
);

create table public.grading_scales (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

create unique index grading_scales_one_active
  on public.grading_scales (is_active)
  where is_active;

create table public.grading_bands (
  id uuid primary key default gen_random_uuid(),
  grading_scale_id uuid not null references public.grading_scales (id) on delete cascade,
  grade text not null check (length(trim(grade)) between 1 and 12),
  minimum_score numeric(7, 2) not null check (minimum_score >= 0),
  maximum_score numeric(7, 2) not null check (maximum_score >= minimum_score),
  remark text,
  created_at timestamptz not null default now(),
  unique (grading_scale_id, grade)
);

create or replace function public.validate_grading_band()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform 1
  from public.grading_scales gs
  where gs.id = new.grading_scale_id
  for update;

  if exists (
    select 1
    from public.grading_bands b
    where b.grading_scale_id = new.grading_scale_id
      and b.id is distinct from new.id
      and new.minimum_score <= b.maximum_score
      and b.minimum_score <= new.maximum_score
  ) then
    raise exception 'Grade score ranges for a grading scale must not overlap';
  end if;
  return new;
end;
$$;

create trigger grading_bands_no_overlap
before insert or update on public.grading_bands
for each row execute function public.validate_grading_band();

create table public.student_subject_results (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null,
  class_id uuid not null,
  academic_session_id uuid not null,
  class_subject_offering_id uuid not null,
  assessment_scheme_id uuid not null,
  term_id uuid not null,
  status public.result_status not null default 'draft',
  submitted_by uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  approved_by uuid references public.profiles (id) on delete set null,
  approved_at timestamptz,
  locked_by uuid references public.profiles (id) on delete set null,
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (student_id, class_id, academic_session_id)
    references public.class_enrollments (student_id, class_id, academic_session_id) on delete restrict,
  foreign key (class_subject_offering_id, class_id, academic_session_id)
    references public.class_subject_offerings (id, class_id, academic_session_id) on delete restrict,
  foreign key (term_id, academic_session_id)
    references public.terms (id, academic_session_id) on delete restrict,
  foreign key (assessment_scheme_id, class_subject_offering_id)
    references public.assessment_schemes (id, class_subject_offering_id) on delete restrict,
  unique (student_id, class_subject_offering_id, term_id),
  unique (id, assessment_scheme_id)
);

create table public.result_component_scores (
  id uuid primary key default gen_random_uuid(),
  result_id uuid not null,
  assessment_scheme_id uuid not null,
  assessment_component_id uuid not null,
  score numeric(7, 2) not null check (score >= 0),
  recorded_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (result_id, assessment_scheme_id)
    references public.student_subject_results (id, assessment_scheme_id) on delete cascade,
  foreign key (assessment_component_id, assessment_scheme_id)
    references public.assessment_components (id, assessment_scheme_id) on delete restrict,
  unique (result_id, assessment_component_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index class_enrollments_class_session_idx
  on public.class_enrollments (class_id, academic_session_id);
create index subject_teacher_assignments_teacher_idx
  on public.subject_teacher_assignments (teacher_id, class_subject_offering_id);
create index student_subject_results_class_term_idx
  on public.student_subject_results (class_id, term_id, status);
create index result_component_scores_result_idx
  on public.result_component_scores (result_id);
create index audit_logs_created_at_idx
  on public.audit_logs (created_at desc);

create or replace function public.is_active_administrator()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'administrator'
      and p.is_active
  );
$$;

create or replace function public.has_scoped_permission(
  p_permission_key text,
  p_class_id uuid,
  p_subject_id uuid,
  p_academic_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when exists (
      select 1
      from public.user_permission_overrides o
      join public.profiles p on p.id = o.user_id and p.is_active
      where o.user_id = auth.uid()
        and o.permission_key = p_permission_key
        and not o.allowed
        and (o.class_id is null or o.class_id = p_class_id)
        and (o.subject_id is null or o.subject_id = p_subject_id)
        and (o.academic_session_id is null or o.academic_session_id = p_academic_session_id)
    ) then false
    else exists (
    select 1
    from public.user_permission_overrides o
    join public.profiles p on p.id = o.user_id and p.is_active
    where o.user_id = auth.uid()
      and o.permission_key = p_permission_key
      and o.allowed
      and (o.class_id is null or o.class_id = p_class_id)
      and (o.subject_id is null or o.subject_id = p_subject_id)
      and (o.academic_session_id is null or o.academic_session_id = p_academic_session_id)
    )
  end;
$$;

create or replace function public.is_scoped_permission_denied(
  p_permission_key text,
  p_class_id uuid,
  p_subject_id uuid,
  p_academic_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.user_permission_overrides o
    join public.profiles p on p.id = o.user_id and p.is_active
    where o.user_id = auth.uid()
      and o.permission_key = p_permission_key
      and not o.allowed
      and (o.class_id is null or o.class_id = p_class_id)
      and (o.subject_id is null or o.subject_id = p_subject_id)
      and (o.academic_session_id is null or o.academic_session_id = p_academic_session_id)
  );
$$;

create or replace function public.can_access_class_session(
  p_class_id uuid,
  p_academic_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_active_administrator()
    or public.has_scoped_permission('register.manage', p_class_id, null, p_academic_session_id)
    or exists (
      select 1
      from public.class_teacher_assignments a
      join public.profiles p on p.id = a.teacher_id and p.is_active
      where a.teacher_id = auth.uid()
        and a.class_id = p_class_id
        and a.academic_session_id = p_academic_session_id
    )
    or exists (
      select 1
      from public.subject_teacher_assignments a
      join public.class_subject_offerings o on o.id = a.class_subject_offering_id
      join public.profiles p on p.id = a.teacher_id and p.is_active
      where a.teacher_id = auth.uid()
        and o.class_id = p_class_id
        and o.academic_session_id = p_academic_session_id
    );
$$;

create or replace function public.can_read_result(p_result_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_active_administrator()
    or exists (
      select 1
      from public.student_subject_results r
      join public.class_subject_offerings o on o.id = r.class_subject_offering_id
      join public.profiles p on p.id = auth.uid() and p.is_active
      where r.id = p_result_id
        and not public.is_scoped_permission_denied('results.read', r.class_id, o.subject_id, r.academic_session_id)
        and (
          public.has_scoped_permission('results.read', r.class_id, o.subject_id, r.academic_session_id)
          or exists (
            select 1 from public.class_teacher_assignments a
            join public.profiles p on p.id = a.teacher_id and p.is_active
            where a.teacher_id = auth.uid()
              and a.class_id = r.class_id
              and a.academic_session_id = r.academic_session_id
          )
          or exists (
            select 1 from public.subject_teacher_assignments a
            join public.profiles p on p.id = a.teacher_id and p.is_active
            where a.teacher_id = auth.uid()
              and a.class_subject_offering_id = r.class_subject_offering_id
          )
        )
    );
$$;

create or replace function public.can_edit_result(p_result_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
      select 1
      from public.student_subject_results r
      join public.class_subject_offerings o on o.id = r.class_subject_offering_id
      join public.profiles p on p.id = auth.uid() and p.is_active
      where r.id = p_result_id
        and r.status = 'draft'
        and not public.is_scoped_permission_denied('results.edit', r.class_id, o.subject_id, r.academic_session_id)
        and (
          (p.role = 'administrator' and p.is_active)
          or
          public.has_scoped_permission('results.edit', r.class_id, o.subject_id, r.academic_session_id)
          or (
            p.role in ('primary_teacher', 'nursery_teacher')
            and exists (
              select 1 from public.class_teacher_assignments a
              where a.teacher_id = auth.uid()
                and a.class_id = r.class_id
                and a.academic_session_id = r.academic_session_id
            )
          )
          or exists (
            select 1 from public.subject_teacher_assignments a
            where a.teacher_id = auth.uid()
              and a.class_subject_offering_id = r.class_subject_offering_id
          )
        )
    );
$$;

create or replace function public.can_create_result(
  p_student_id uuid,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_class_subject_offering_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_active_administrator()
    or exists (
      select 1
      from public.class_subject_offerings o
      join public.profiles p on p.id = auth.uid() and p.is_active
      where o.id = p_class_subject_offering_id
        and o.class_id = p_class_id
        and o.academic_session_id = p_academic_session_id
        and not public.is_scoped_permission_denied('results.edit', p_class_id, o.subject_id, p_academic_session_id)
        and exists (
          select 1 from public.class_enrollments e
          where e.student_id = p_student_id
            and e.class_id = p_class_id
            and e.academic_session_id = p_academic_session_id
        )
        and (
          public.has_scoped_permission('results.edit', p_class_id, o.subject_id, p_academic_session_id)
          or (
            p.role in ('primary_teacher', 'nursery_teacher')
            and exists (
              select 1 from public.class_teacher_assignments a
              where a.teacher_id = auth.uid()
                and a.class_id = p_class_id
                and a.academic_session_id = p_academic_session_id
            )
          )
          or exists (
            select 1 from public.subject_teacher_assignments a
            where a.teacher_id = auth.uid()
              and a.class_subject_offering_id = o.id
          )
        )
    );
$$;

create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator()
     and (new.role is distinct from old.role
       or new.is_active is distinct from old.is_active
       or new.must_change_password is distinct from old.must_change_password) then
    raise exception 'Only an administrator may change profile privileges';
  end if;

  if new.role is distinct from old.role
     and (
       (
         new.role not in (
           'secondary_class_teacher', 'primary_teacher', 'nursery_teacher'
         )
         and exists (
           select 1 from public.class_teacher_assignments a
           where a.teacher_id = new.id
         )
       )
       or (
         new.role <> 'secondary_subject_teacher'
         and exists (
           select 1 from public.subject_teacher_assignments a
           where a.teacher_id = new.id
         )
       )
     ) then
    raise exception 'Reassign this user''s classes and subjects before changing their role';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_protect_privileges
before update on public.profiles
for each row execute function public.protect_profile_privileges();

create or replace function public.validate_component_score()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  component_max numeric(7, 2);
begin
  select c.max_score into component_max
  from public.assessment_components c
  where c.id = new.assessment_component_id
    and c.assessment_scheme_id = new.assessment_scheme_id;

  if component_max is null then
    raise exception 'Assessment component does not belong to this assessment scheme';
  end if;

  if new.score > component_max then
    raise exception 'Score exceeds the configured maximum of %', component_max;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger result_component_scores_validate
before insert or update on public.result_component_scores
for each row execute function public.validate_component_score();

create or replace function public.guard_result_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if public.is_active_administrator() then
    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.submitted_by is not null
       or new.submitted_at is not null
       or new.reviewed_by is not null
       or new.reviewed_at is not null
       or new.approved_by is not null
       or new.approved_at is not null
       or new.locked_by is not null
       or new.locked_at is not null then
      raise exception 'Only an administrator may set result workflow metadata';
    end if;
  else
    if new.student_id is distinct from old.student_id
       or new.class_id is distinct from old.class_id
       or new.academic_session_id is distinct from old.academic_session_id
       or new.class_subject_offering_id is distinct from old.class_subject_offering_id
       or new.assessment_scheme_id is distinct from old.assessment_scheme_id
       or new.term_id is distinct from old.term_id then
      raise exception 'Result identity fields cannot be changed';
    end if;

    if new.status is distinct from old.status
       and not (old.status = 'draft' and new.status = 'submitted') then
      raise exception 'Teachers may only submit draft results';
    end if;

    if old.status = 'draft' and new.status = 'submitted' then
      new.submitted_by := auth.uid();
      new.submitted_at := now();
    else
      new.submitted_by := old.submitted_by;
      new.submitted_at := old.submitted_at;
    end if;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.approved_by := old.approved_by;
    new.approved_at := old.approved_at;
    new.locked_by := old.locked_by;
    new.locked_at := old.locked_at;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger student_subject_results_guard
before insert or update on public.student_subject_results
for each row execute function public.guard_result_changes();

create or replace function public.log_result_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  changed_fields text[];
  old_status text;
  new_status text;
begin
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_fields
    from jsonb_each(to_jsonb(new)) n
    join jsonb_each(to_jsonb(old)) o using (key)
    where n.value is distinct from o.value
      and key not in ('updated_at');
  end if;

  old_status := case when tg_op = 'INSERT' then null else old.status::text end;
  new_status := case when tg_op = 'DELETE' then null else new.status::text end;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    lower(tg_op),
    'student_subject_result',
    coalesce(new.id, old.id)::text,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', old_status,
      'current_status', new_status,
      'changed_fields', changed_fields
    ))
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger student_subject_results_audit
after insert or update or delete on public.student_subject_results
for each row execute function public.log_result_change();

create or replace function public.log_component_score_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    lower(tg_op),
    'result_component_score',
    coalesce(new.id, old.id)::text,
    jsonb_strip_nulls(jsonb_build_object(
      'result_id', coalesce(new.result_id, old.result_id),
      'assessment_component_id', coalesce(new.assessment_component_id, old.assessment_component_id),
      'previous_score', case when tg_op = 'INSERT' then null else old.score end,
      'current_score', case when tg_op = 'DELETE' then null else new.score end
    ))
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger result_component_scores_audit
after insert or update or delete on public.result_component_scores
for each row execute function public.log_component_score_change();

alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.academic_sessions enable row level security;
alter table public.terms enable row level security;
alter table public.students enable row level security;
alter table public.class_enrollments enable row level security;
alter table public.class_teacher_assignments enable row level security;
alter table public.class_subject_offerings enable row level security;
alter table public.subject_teacher_assignments enable row level security;
alter table public.user_permission_overrides enable row level security;
alter table public.assessment_schemes enable row level security;
alter table public.assessment_components enable row level security;
alter table public.grading_scales enable row level security;
alter table public.grading_bands enable row level security;
alter table public.student_subject_results enable row level security;
alter table public.result_component_scores enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_read_self_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_active_administrator());
create policy profiles_update_self_or_admin on public.profiles
for update to authenticated
using (id = auth.uid() or public.is_active_administrator())
with check (id = auth.uid() or public.is_active_administrator());

create policy classes_read_assigned on public.classes
for select to authenticated
using (
  public.is_active_administrator()
  or exists (
    select 1 from public.class_teacher_assignments a
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where a.class_id = classes.id and a.teacher_id = auth.uid()
  )
  or exists (
    select 1 from public.class_subject_offerings o
    join public.subject_teacher_assignments a on a.class_subject_offering_id = o.id
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where o.class_id = classes.id and a.teacher_id = auth.uid()
  )
);
create policy classes_admin_write on public.classes
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy subjects_read_assigned on public.subjects
for select to authenticated
using (
  public.is_active_administrator()
  or exists (
    select 1 from public.class_subject_offerings o
    join public.subject_teacher_assignments a on a.class_subject_offering_id = o.id
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where o.subject_id = subjects.id and a.teacher_id = auth.uid()
  )
  or exists (
    select 1 from public.class_teacher_assignments a
    join public.class_subject_offerings o
      on o.class_id = a.class_id and o.academic_session_id = a.academic_session_id
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where o.subject_id = subjects.id and a.teacher_id = auth.uid()
  )
);
create policy subjects_admin_write on public.subjects
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy sessions_read_authenticated on public.academic_sessions
for select to authenticated using (true);
create policy sessions_admin_write on public.academic_sessions
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());
create policy terms_read_authenticated on public.terms
for select to authenticated using (true);
create policy terms_admin_write on public.terms
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy students_read_assigned on public.students
for select to authenticated
using (
  public.is_active_administrator()
  or exists (
    select 1 from public.class_enrollments e
    where e.student_id = students.id
      and public.can_access_class_session(e.class_id, e.academic_session_id)
  )
);
create policy students_admin_write on public.students
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy enrollments_read_assigned on public.class_enrollments
for select to authenticated
using (public.can_access_class_session(class_id, academic_session_id));
create policy enrollments_admin_manage on public.class_enrollments
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());
create policy enrollments_class_teacher_manage on public.class_enrollments
for insert to authenticated
with check (
  public.has_scoped_permission('register.manage', class_id, null, academic_session_id)
  or (
    not public.is_scoped_permission_denied('register.manage', class_id, null, academic_session_id)
    and exists (
    select 1 from public.class_teacher_assignments a
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where a.teacher_id = auth.uid()
      and a.class_id = class_enrollments.class_id
      and a.academic_session_id = class_enrollments.academic_session_id
    )
  )
);
create policy enrollments_class_teacher_update on public.class_enrollments
for update to authenticated
using (
  public.has_scoped_permission('register.manage', class_id, null, academic_session_id)
  or (
    not public.is_scoped_permission_denied('register.manage', class_id, null, academic_session_id)
    and exists (
    select 1 from public.class_teacher_assignments a
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where a.teacher_id = auth.uid()
      and a.class_id = class_enrollments.class_id
      and a.academic_session_id = class_enrollments.academic_session_id
    )
  )
)
with check (
  public.has_scoped_permission('register.manage', class_id, null, academic_session_id)
  or (
    not public.is_scoped_permission_denied('register.manage', class_id, null, academic_session_id)
    and exists (
    select 1 from public.class_teacher_assignments a
    join public.profiles p on p.id = a.teacher_id and p.is_active
    where a.teacher_id = auth.uid()
      and a.class_id = class_enrollments.class_id
      and a.academic_session_id = class_enrollments.academic_session_id
    )
  )
);

create policy class_teacher_assignments_read on public.class_teacher_assignments
for select to authenticated
using (
  public.is_active_administrator()
  or (
    teacher_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active)
  )
);
create policy class_teacher_assignments_admin_manage on public.class_teacher_assignments
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy class_subject_offerings_read_assigned on public.class_subject_offerings
for select to authenticated
using (public.can_access_class_session(class_id, academic_session_id));
create policy class_subject_offerings_admin_manage on public.class_subject_offerings
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy subject_teacher_assignments_read on public.subject_teacher_assignments
for select to authenticated
using (
  public.is_active_administrator()
  or (
    teacher_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active)
  )
);
create policy subject_teacher_assignments_admin_manage on public.subject_teacher_assignments
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy permission_overrides_read on public.user_permission_overrides
for select to authenticated
using (
  public.is_active_administrator()
  or (
    user_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active)
  )
);
create policy permission_overrides_admin_manage on public.user_permission_overrides
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator() and granted_by = auth.uid());

create policy assessment_schemes_read_assigned on public.assessment_schemes
for select to authenticated
using (
  exists (
    select 1 from public.class_subject_offerings o
    where o.id = class_subject_offering_id
      and public.can_access_class_session(o.class_id, o.academic_session_id)
  )
);
create policy assessment_schemes_admin_manage on public.assessment_schemes
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy assessment_components_read_assigned on public.assessment_components
for select to authenticated
using (
  exists (
    select 1
    from public.assessment_schemes s
    join public.class_subject_offerings o on o.id = s.class_subject_offering_id
    where s.id = assessment_scheme_id
      and public.can_access_class_session(o.class_id, o.academic_session_id)
  )
);
create policy assessment_components_admin_manage on public.assessment_components
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy grading_scales_read_authenticated on public.grading_scales
for select to authenticated using (true);
create policy grading_scales_admin_manage on public.grading_scales
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());
create policy grading_bands_read_authenticated on public.grading_bands
for select to authenticated using (true);
create policy grading_bands_admin_manage on public.grading_bands
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create policy results_read_assigned on public.student_subject_results
for select to authenticated
using (public.can_read_result(id));
create policy results_insert_authorized on public.student_subject_results
for insert to authenticated
with check (
  status = 'draft'
  and public.can_create_result(student_id, class_id, academic_session_id, class_subject_offering_id)
);
create policy results_update_authorized on public.student_subject_results
for update to authenticated
using (public.is_active_administrator() or public.can_edit_result(id))
with check (
  public.is_active_administrator()
  or (
    status in ('draft', 'submitted')
    and public.can_edit_result(id)
  )
);
create policy component_scores_read_authorized on public.result_component_scores
for select to authenticated
using (public.can_read_result(result_id));
create policy component_scores_insert_authorized on public.result_component_scores
for insert to authenticated
with check (public.can_edit_result(result_id) and recorded_by = auth.uid());
create policy component_scores_update_authorized on public.result_component_scores
for update to authenticated
using (public.can_edit_result(result_id))
with check (public.can_edit_result(result_id));
create policy component_scores_admin_delete on public.result_component_scores
for delete to authenticated
using (public.is_active_administrator());

create policy audit_logs_admin_read on public.audit_logs
for select to authenticated
using (public.is_active_administrator());

revoke all on all tables in schema public from anon;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.classes, public.subjects,
  public.academic_sessions, public.terms, public.students,
  public.class_enrollments, public.class_teacher_assignments,
  public.class_subject_offerings, public.subject_teacher_assignments,
  public.user_permission_overrides, public.assessment_schemes,
  public.assessment_components, public.grading_scales, public.grading_bands,
  public.result_component_scores to authenticated;
grant select, insert, update on public.student_subject_results to authenticated;
grant select on public.audit_logs to authenticated;
grant usage, select on all sequences in schema public to authenticated;

revoke all on function public.is_active_administrator() from public;
revoke all on function public.has_scoped_permission(text, uuid, uuid, uuid) from public;
revoke all on function public.is_scoped_permission_denied(text, uuid, uuid, uuid) from public;
revoke all on function public.can_access_class_session(uuid, uuid) from public;
revoke all on function public.can_read_result(uuid) from public;
revoke all on function public.can_edit_result(uuid) from public;
revoke all on function public.can_create_result(uuid, uuid, uuid, uuid) from public;
grant execute on function public.is_active_administrator() to authenticated;
grant execute on function public.has_scoped_permission(text, uuid, uuid, uuid) to authenticated;
grant execute on function public.is_scoped_permission_denied(text, uuid, uuid, uuid) to authenticated;
grant execute on function public.can_access_class_session(uuid, uuid) to authenticated;
grant execute on function public.can_read_result(uuid) to authenticated;
grant execute on function public.can_edit_result(uuid) to authenticated;
grant execute on function public.can_create_result(uuid, uuid, uuid, uuid) to authenticated;
