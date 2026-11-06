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
        or public.has_scoped_permission('results.edit', r.class_id, o.subject_id, r.academic_session_id)
        or exists (
          select 1
          from public.subject_teacher_assignments a
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
          select 1
          from public.class_enrollments e
          where e.student_id = p_student_id
            and e.class_id = p_class_id
            and e.academic_session_id = p_academic_session_id
        )
        and (
          public.has_scoped_permission('results.edit', p_class_id, o.subject_id, p_academic_session_id)
          or exists (
            select 1
            from public.subject_teacher_assignments a
            where a.teacher_id = auth.uid()
              and a.class_subject_offering_id = o.id
          )
        )
    );
$$;

revoke all on function public.can_edit_result(uuid) from public;
grant execute on function public.can_edit_result(uuid) to authenticated;
revoke all on function public.can_create_result(uuid, uuid, uuid, uuid) from public;
grant execute on function public.can_create_result(uuid, uuid, uuid, uuid) to authenticated;
