create or replace function public.configure_class_subject(
  p_class_id uuid,
  p_academic_session_id uuid,
  p_subject_name text,
  p_components jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_subject_id uuid;
  offering_id uuid;
  scheme_id uuid;
  component jsonb;
  component_count integer;
  expected_order integer := 0;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can configure class subjects'
      using errcode = '42501';
  end if;

  if p_subject_name is null or length(trim(p_subject_name)) not between 1 and 120 then
    raise exception 'Enter a valid subject name';
  end if;

  if p_components is null or jsonb_typeof(p_components) <> 'array' then
    raise exception 'Assessment components must be supplied as a list';
  end if;

  component_count := jsonb_array_length(p_components);
  if component_count < 1 or component_count > 10 then
    raise exception 'Configure between 1 and 10 assessment components';
  end if;

  if not exists (
    select 1 from public.classes c
    where c.id = p_class_id and c.is_active
  ) or not exists (
    select 1 from public.academic_sessions s
    where s.id = p_academic_session_id
  ) then
    raise exception 'Select an active class and academic session';
  end if;

  select s.id into v_subject_id
  from public.subjects s
  where lower(s.name) = lower(trim(p_subject_name))
  limit 1;

  if v_subject_id is null then
    insert into public.subjects (name)
    values (trim(p_subject_name))
    returning id into v_subject_id;
  else
    update public.subjects
    set is_active = true
    where id = v_subject_id;
  end if;

  insert into public.class_subject_offerings (
    class_id, subject_id, academic_session_id, is_active
  )
  values (p_class_id, v_subject_id, p_academic_session_id, true)
  on conflict (class_id, subject_id, academic_session_id) do update
    set is_active = true
  returning id into offering_id;

  if exists (
    select 1 from public.assessment_schemes a
    where a.class_subject_offering_id = offering_id
  ) then
    raise exception 'This subject already has an assessment scheme for the selected class and session';
  end if;

  insert into public.assessment_schemes (class_subject_offering_id, name)
  values (offering_id, 'Assessment scheme for ' || trim(p_subject_name))
  returning id into scheme_id;

  for component in select value from jsonb_array_elements(p_components)
  loop
    expected_order := expected_order + 1;
    if nullif(trim(component->>'code'), '') is null
       or nullif(trim(component->>'name'), '') is null
       or coalesce((component->>'max_score')::numeric, 0) <= 0 then
      raise exception 'Each assessment component needs a code, name, and positive maximum score';
    end if;

    insert into public.assessment_components (
      assessment_scheme_id, code, name, max_score, display_order,
      counts_toward_total, is_required
    )
    values (
      scheme_id,
      trim(component->>'code'),
      trim(component->>'name'),
      (component->>'max_score')::numeric,
      expected_order,
      coalesce((component->>'counts_toward_total')::boolean, true),
      coalesce((component->>'is_required')::boolean, true)
    );
  end loop;

  return offering_id;
end;
$$;

revoke all on function public.configure_class_subject(uuid, uuid, text, jsonb) from public;
grant execute on function public.configure_class_subject(uuid, uuid, text, jsonb) to authenticated;
