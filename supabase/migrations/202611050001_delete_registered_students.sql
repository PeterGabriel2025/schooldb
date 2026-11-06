create or replace function public.delete_registered_student(
  p_student_id uuid,
  p_class_id uuid,
  p_academic_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  student_record public.students%rowtype;
  enrollment_record record;
  enrollment_count integer := 0;
begin
  select *
  into student_record
  from public.students
  where id = p_student_id
  for update;

  if not found then
    raise exception 'Student not found';
  end if;

  if not exists (
    select 1
    from public.class_enrollments
    where student_id = p_student_id
      and class_id = p_class_id
      and academic_session_id = p_academic_session_id
  ) then
    raise exception 'Student is not enrolled in the selected class and session';
  end if;

  for enrollment_record in
    select class_id, academic_session_id
    from public.class_enrollments
    where student_id = p_student_id
    order by academic_session_id, class_id
    for update
  loop
    enrollment_count := enrollment_count + 1;
    if not public.can_manage_class_register(
      enrollment_record.class_id,
      enrollment_record.academic_session_id
    ) then
      raise exception 'Not authorized to delete this student and all of their enrollments'
        using errcode = '42501';
    end if;
  end loop;

  if exists (
    select 1
    from public.student_subject_results
    where student_id = p_student_id
  ) then
    raise exception 'This student has saved results and cannot be permanently deleted';
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'delete',
    'student',
    p_student_id::text,
    jsonb_build_object(
      'admission_number', student_record.admission_number,
      'student_name', concat_ws(' ', student_record.first_name, student_record.other_names, student_record.last_name),
      'enrollments_deleted', enrollment_count
    )
  );

  delete from public.class_enrollments
  where student_id = p_student_id;

  delete from public.students
  where id = p_student_id;
end;
$$;

revoke all on function public.delete_registered_student(uuid, uuid, uuid) from public;
grant execute on function public.delete_registered_student(uuid, uuid, uuid) to authenticated;
