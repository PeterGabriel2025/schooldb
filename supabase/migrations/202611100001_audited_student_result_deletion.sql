create or replace function public.delete_student_subject_result(
  p_result_id uuid,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_class_subject_offering_id uuid,
  p_term_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  result_record public.student_subject_results%rowtype;
  is_admin boolean := public.is_active_administrator();
begin
  if p_reason is null or length(trim(p_reason)) < 10 then
    raise exception 'Provide a deletion reason of at least 10 characters';
  end if;

  select *
  into result_record
  from public.student_subject_results
  where id = p_result_id
    and class_id = p_class_id
    and academic_session_id = p_academic_session_id
    and class_subject_offering_id = p_class_subject_offering_id
    and term_id = p_term_id
  for update;

  if not found then
    raise exception 'The result was not found or no longer matches the selected class, subject, and term';
  end if;

  if not is_admin
     and (
       result_record.status <> 'draft'
       or not public.can_edit_result(result_record.id)
     ) then
    raise exception 'Only an administrator may delete submitted, reviewed, approved, or locked results'
      using errcode = '42501';
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'delete_result',
    'student_subject_result',
    result_record.id::text,
    jsonb_build_object(
      'reason', trim(p_reason),
      'previous_status', result_record.status,
      'student_id', result_record.student_id,
      'class_id', result_record.class_id,
      'academic_session_id', result_record.academic_session_id,
      'class_subject_offering_id', result_record.class_subject_offering_id,
      'term_id', result_record.term_id
    )
  );

  delete from public.student_subject_results
  where id = result_record.id;
end;
$$;

revoke all on function public.delete_student_subject_result(uuid, uuid, uuid, uuid, uuid, text)
  from public, anon;
grant execute on function public.delete_student_subject_result(uuid, uuid, uuid, uuid, uuid, text)
  to authenticated;
