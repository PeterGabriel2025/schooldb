create or replace function public.update_registered_student(
  p_student_id uuid,
  p_admission_number text,
  p_first_name text,
  p_last_name text,
  p_other_names text default null,
  p_gender text default null,
  p_date_of_birth date default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  enrollment_record record;
begin
  select e.student_id, e.class_id, e.academic_session_id
  into enrollment_record
  from public.class_enrollments e
  where e.student_id = p_student_id
    and e.left_on is null
  order by e.created_at desc
  limit 1;

  if enrollment_record.student_id is null then
    raise exception 'The student is not currently enrolled in a class';
  end if;

  if not public.can_manage_class_register(
    enrollment_record.class_id,
    enrollment_record.academic_session_id
  ) then
    raise exception 'Not authorized to edit this student register entry'
      using errcode = '42501';
  end if;

  if p_first_name is null or length(trim(p_first_name)) = 0
     or p_last_name is null or length(trim(p_last_name)) = 0
     or p_admission_number is null or length(trim(p_admission_number)) = 0 then
    raise exception 'Admission number, first name and last name are required';
  end if;

  update public.students
  set admission_number = trim(p_admission_number),
      first_name = trim(p_first_name),
      last_name = trim(p_last_name),
      other_names = nullif(trim(p_other_names), ''),
      gender = nullif(trim(p_gender), ''),
      date_of_birth = p_date_of_birth,
      updated_at = now()
  where id = p_student_id;
end;
$$;

revoke all on function public.update_registered_student(uuid, text, text, text, text, text, date) from public;
grant execute on function public.update_registered_student(uuid, text, text, text, text, text, date) to authenticated;
