create or replace function public.can_manage_class_register(
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
    or (
      public.has_scoped_permission(
        'register.manage', p_class_id, null, p_academic_session_id
      )
      and not public.is_scoped_permission_denied(
        'register.manage', p_class_id, null, p_academic_session_id
      )
      and exists (
        select 1
        from public.class_teacher_assignments a
        join public.profiles p on p.id = a.teacher_id and p.is_active
        where a.teacher_id = auth.uid()
          and a.class_id = p_class_id
          and a.academic_session_id = p_academic_session_id
      )
    );
$$;

revoke all on function public.can_manage_class_register(uuid, uuid) from public;
grant execute on function public.can_manage_class_register(uuid, uuid) to authenticated;
