create or replace function public.validate_class_teacher_assignment_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  assigned_role public.app_role;
  assigned_stage public.school_stage;
begin
  select tr.role into assigned_role
  from public.profiles p
  join public.teacher_roles tr on tr.teacher_id = p.id
  where p.id = new.teacher_id and p.is_active
    and tr.role in ('secondary_class_teacher', 'primary_teacher', 'nursery_teacher')
  limit 1;

  select c.stage into assigned_stage
  from public.classes c
  where c.id = new.class_id;

  if assigned_role is null or assigned_role not in (
    'secondary_class_teacher', 'primary_teacher', 'nursery_teacher'
  ) then
    raise exception 'The assigned user is not an active class teacher';
  end if;
  if (assigned_stage = 'secondary' and not exists (
      select 1 from public.teacher_roles where teacher_id = new.teacher_id and role = 'secondary_class_teacher'
    ))
    or (assigned_stage = 'primary' and not exists (
      select 1 from public.teacher_roles where teacher_id = new.teacher_id and role = 'primary_teacher'
    ))
    or (assigned_stage = 'nursery' and not exists (
      select 1 from public.teacher_roles where teacher_id = new.teacher_id and role = 'nursery_teacher'
    )) then
    raise exception 'The teacher role does not match the selected class section';
  end if;
  return new;
end;
$$;

create or replace function public.validate_subject_teacher_assignment_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  has_valid_role boolean;
  assigned_stage public.school_stage;
begin
  select exists (
    select 1 from public.profiles p
    join public.teacher_roles tr on tr.teacher_id = p.id
    where p.id = new.teacher_id and p.is_active
      and tr.role in ('secondary_subject_teacher', 'primary_teacher', 'nursery_teacher')
  ) into has_valid_role;

  select c.stage into assigned_stage
  from public.class_subject_offerings o
  join public.classes c on c.id = o.class_id
  where o.id = new.class_subject_offering_id;

  if not has_valid_role then
    raise exception 'The assigned user is not an active subject teacher';
  end if;
  if assigned_stage = 'secondary' and not exists (
    select 1 from public.teacher_roles where teacher_id = new.teacher_id and role = 'secondary_subject_teacher'
  ) then
    raise exception 'The teacher does not have the secondary subject teacher role';
  elsif assigned_stage = 'primary' and not exists (
    select 1 from public.teacher_roles where teacher_id = new.teacher_id and role = 'primary_teacher'
  ) then
    raise exception 'The teacher does not have the primary teacher role';
  elsif assigned_stage = 'nursery' and not exists (
    select 1 from public.teacher_roles where teacher_id = new.teacher_id and role = 'nursery_teacher'
  ) then
    raise exception 'The teacher does not have the nursery teacher role';
  end if;
  return new;
end;
$$;
