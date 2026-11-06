create or replace function public.admin_set_user_permissions(
  p_user_id uuid,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  permission_record jsonb;
  permission_key text;
  permission_allowed boolean;
  has_class_role boolean;
  has_subject_role boolean;
  has_any_teacher_role boolean;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can manage permissions'
      using errcode = '42501';
  end if;
  if p_user_id is null or not exists (
    select 1 from public.profiles
    where id = p_user_id and is_active and role <> 'administrator'
  ) then
    raise exception 'Select an active teacher';
  end if;
  if p_permissions is null or jsonb_typeof(p_permissions) <> 'array' then
    raise exception 'Permissions must be supplied as a list';
  end if;

  select
    exists (select 1 from public.teacher_roles where teacher_id = p_user_id
      and role in ('secondary_class_teacher', 'primary_teacher', 'nursery_teacher')),
    exists (select 1 from public.teacher_roles where teacher_id = p_user_id
      and role in ('secondary_subject_teacher', 'primary_teacher', 'nursery_teacher')),
    exists (select 1 from public.teacher_roles where teacher_id = p_user_id)
  into has_class_role, has_subject_role, has_any_teacher_role;

  if not has_any_teacher_role then
    raise exception 'The selected teacher has no assigned teacher role';
  end if;

  delete from public.user_permission_overrides
  where user_id = p_user_id
    and class_id is null
    and subject_id is null
    and academic_session_id is null;

  for permission_record in select value from jsonb_array_elements(p_permissions)
  loop
    permission_key := permission_record->>'permission_key';
    permission_allowed := (permission_record->>'allowed')::boolean;
    if permission_key not in ('register.manage', 'results.read', 'results.edit')
       or permission_allowed is null then
      raise exception 'Invalid permission grant';
    end if;
    if permission_allowed and (
      (permission_key = 'register.manage' and not has_class_role)
      or (permission_key = 'results.edit' and not has_subject_role)
      or (permission_key = 'results.read' and not has_any_teacher_role)
    ) then
      raise exception 'The selected permission does not match the teacher''s role';
    end if;
    insert into public.user_permission_overrides (
      user_id, permission_key, allowed, granted_by
    )
    values (p_user_id, permission_key, permission_allowed, auth.uid());
  end loop;
end;
$$;

revoke all on function public.admin_set_user_permissions(uuid, jsonb) from public;
grant execute on function public.admin_set_user_permissions(uuid, jsonb) to authenticated;
