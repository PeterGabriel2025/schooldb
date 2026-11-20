create or replace function public.admin_update_teacher_assignments(
  p_teacher_id uuid,
  p_full_name text,
  p_roles text[],
  p_class_ids uuid[],
  p_offering_ids uuid[],
  p_academic_session_id uuid,
  p_term_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  selected_role text;
  has_class_assignments boolean := coalesce(cardinality(p_class_ids), 0) > 0;
  has_subject_assignments boolean := coalesce(cardinality(p_offering_ids), 0) > 0;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can edit teacher assignments'
      using errcode = '42501';
  end if;
  if p_teacher_id is null or not exists (
    select 1 from public.profiles
    where id = p_teacher_id and role <> 'administrator'
  ) then
    raise exception 'Select a valid teacher account';
  end if;
  if p_full_name is null or length(trim(p_full_name)) not between 1 and 160 then
    raise exception 'Enter a valid teacher name';
  end if;
  if coalesce(cardinality(p_roles), 0) = 0 then
    raise exception 'Select at least one teacher role';
  end if;
  foreach selected_role in array p_roles loop
    if selected_role not in (
      'secondary_subject_teacher',
      'secondary_class_teacher',
      'primary_teacher',
      'nursery_teacher'
    ) then
      raise exception 'Invalid teacher role';
    end if;
  end loop;
  if (has_class_assignments or has_subject_assignments)
     and (p_academic_session_id is null or p_term_id is null) then
    raise exception 'Select an academic session and term for the assignments';
  end if;
  if p_term_id is not null and not exists (
    select 1 from public.terms
    where id = p_term_id and academic_session_id = p_academic_session_id
  ) then
    raise exception 'The selected term does not belong to the selected academic session';
  end if;
  if has_subject_assignments and exists (
    select 1 from public.class_subject_offerings
    where id = any(p_offering_ids)
      and academic_session_id <> p_academic_session_id
  ) then
    raise exception 'Every subject offering must belong to the selected academic session';
  end if;

  update public.profiles
  set full_name = trim(p_full_name),
      role = p_roles[1]::public.app_role
  where id = p_teacher_id;

  delete from public.teacher_roles where teacher_id = p_teacher_id;
  insert into public.teacher_roles (teacher_id, role)
  select p_teacher_id, role_name::public.app_role
  from (select distinct unnest(p_roles) as role_name) roles;

  delete from public.class_teacher_assignments a
  using public.classes c
  where a.teacher_id = p_teacher_id
    and a.class_id = c.id
    and not (
      (c.stage = 'secondary' and exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id and role = 'secondary_class_teacher'
      ))
      or (c.stage = 'primary' and exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id and role = 'primary_teacher'
      ))
      or (c.stage = 'nursery' and exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id and role = 'nursery_teacher'
      ))
    );
  delete from public.subject_teacher_assignments a
  using public.class_subject_offerings o, public.classes c
  where a.teacher_id = p_teacher_id
    and a.class_subject_offering_id = o.id
    and o.class_id = c.id
    and not (
      (c.stage = 'secondary' and exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id and role = 'secondary_subject_teacher'
      ))
      or (c.stage = 'primary' and exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id and role = 'primary_teacher'
      ))
      or (c.stage = 'nursery' and exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id and role = 'nursery_teacher'
      ))
    );

  delete from public.user_permission_overrides
  where user_id = p_teacher_id
    and allowed
    and (
      (permission_key = 'register.manage' and not exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id
          and role in ('secondary_class_teacher', 'primary_teacher', 'nursery_teacher')
      ))
      or (permission_key = 'results.edit' and not exists (
        select 1 from public.teacher_roles
        where teacher_id = p_teacher_id
          and role in ('secondary_subject_teacher', 'primary_teacher', 'nursery_teacher')
      ))
      or (permission_key = 'results.read' and not exists (
        select 1 from public.teacher_roles where teacher_id = p_teacher_id
      ))
    );

  delete from public.class_teacher_assignments
  where teacher_id = p_teacher_id
    and academic_session_id = p_academic_session_id
    and term_id = p_term_id;
  delete from public.subject_teacher_assignments a
  using public.class_subject_offerings o
  where a.teacher_id = p_teacher_id
    and a.class_subject_offering_id = o.id
    and o.academic_session_id = p_academic_session_id
    and a.term_id = p_term_id;

  if has_class_assignments then
    insert into public.class_teacher_assignments (
      teacher_id, class_id, academic_session_id, term_id
    )
    select p_teacher_id, class_id, p_academic_session_id, p_term_id
    from (select distinct unnest(p_class_ids) as class_id) classes;
  end if;

  if has_subject_assignments then
    insert into public.subject_teacher_assignments (
      teacher_id, class_subject_offering_id, term_id
    )
    select p_teacher_id, offering_id, p_term_id
    from (select distinct unnest(p_offering_ids) as offering_id) offerings;
  end if;
end;
$$;
