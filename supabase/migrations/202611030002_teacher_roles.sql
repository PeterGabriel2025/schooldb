create table if not exists public.teacher_roles (
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  primary key (teacher_id, role),
  check (role <> 'administrator')
);

insert into public.teacher_roles (teacher_id, role)
select id, role from public.profiles
where role <> 'administrator'
on conflict do nothing;

alter table public.teacher_roles enable row level security;

create policy teacher_roles_admin_manage on public.teacher_roles
for all to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create or replace function public.validate_class_teacher_assignment_role()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = new.teacher_id and p.is_active and p.role <> 'administrator'
  ) then
    raise exception 'The assigned user is not an active teacher';
  end if;
  return new;
end;
$$;

create or replace function public.validate_subject_teacher_assignment_role()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = new.teacher_id and p.is_active and p.role <> 'administrator'
  ) then
    raise exception 'The assigned user is not an active teacher';
  end if;
  return new;
end;
$$;
