revoke all on function public.admin_add_subject_offering(uuid, uuid, text)
  from public, authenticated;

create or replace function public.admin_add_subject_to_class_group(
  p_class_group text,
  p_academic_session_id uuid,
  p_subject_name text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  section_stage public.school_stage;
  class_name_pattern text;
  matching_class_count integer;
  class_record record;
  added_count integer := 0;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can add subjects'
      using errcode = '42501';
  end if;
  if p_subject_name is null or length(trim(p_subject_name)) not between 1 and 120 then
    raise exception 'Enter a valid subject name';
  end if;
  if not exists (
    select 1 from public.academic_sessions s
    where s.id = p_academic_session_id and s.is_active
  ) then
    raise exception 'Select an active academic session';
  end if;

  case p_class_group
    when 'junior_secondary' then
      section_stage := 'secondary';
      class_name_pattern := '^JSS[[:space:]]*[1-3]([^0-9].*)?$';
    when 'senior_secondary' then
      section_stage := 'secondary';
      class_name_pattern := '^SSS[[:space:]]*[1-3]([^0-9].*)?$';
    when 'upper_basic' then
      section_stage := 'primary';
      class_name_pattern := '^BASIC[[:space:]]*[4-6]([^0-9].*)?$';
    when 'lower_basic' then
      section_stage := 'primary';
      class_name_pattern := '^BASIC[[:space:]]*[1-3]([^0-9].*)?$';
    when 'nursery' then
      section_stage := 'nursery';
      class_name_pattern := '^NURSERY[[:space:]]*[1-3]([^0-9].*)?$';
    when 'pre_nursery' then
      section_stage := 'nursery';
      class_name_pattern := '^PRE[-[:space:]]*NURSERY$';
    else
      raise exception 'Select a valid school level';
  end case;

  if not exists (
    select 1 from public.section_assessment_settings settings
    where settings.stage = section_stage
  ) then
    raise exception 'Configure the shared assessment scheme for this school section before adding subjects';
  end if;

  select count(*) into matching_class_count
  from public.classes c
  where c.is_active
    and c.stage = section_stage
    and regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g') ~ class_name_pattern;
  if matching_class_count = 0 then
    raise exception 'No active classes were found in the selected school level';
  end if;

  for class_record in
    select c.id
    from public.classes c
    where c.is_active
      and c.stage = section_stage
      and regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g') ~ class_name_pattern
    order by c.name
  loop
    perform public.admin_add_subject_offering(
      class_record.id,
      p_academic_session_id,
      trim(p_subject_name)
    );
    added_count := added_count + 1;
  end loop;

  return added_count;
end;
$$;

revoke all on function public.admin_add_subject_to_class_group(text, uuid, text)
  from public;
grant execute on function public.admin_add_subject_to_class_group(text, uuid, text)
  to authenticated;
