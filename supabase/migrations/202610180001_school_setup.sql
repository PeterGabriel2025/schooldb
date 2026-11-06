create or replace function public.create_academic_session(
  p_name text,
  p_starts_on date,
  p_ends_on date,
  p_active_term smallint,
  p_make_current boolean
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  new_session_id uuid;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can create academic sessions'
      using errcode = '42501';
  end if;

  if p_active_term is null or p_active_term not between 1 and 3 then
    raise exception 'Select a valid active term';
  end if;

  if p_make_current is null then
    raise exception 'Specify whether this should be the current session';
  end if;
  if p_make_current then
    update public.academic_sessions
    set is_current = false
    where is_current;
  end if;

  insert into public.academic_sessions (name, starts_on, ends_on, is_current)
  values (trim(p_name), p_starts_on, p_ends_on, p_make_current)
  returning id into new_session_id;

  insert into public.terms (academic_session_id, term_number, name, is_active)
  values
    (new_session_id, 1, 'First Term', p_active_term = 1),
    (new_session_id, 2, 'Second Term', p_active_term = 2),
    (new_session_id, 3, 'Third Term', p_active_term = 3);

  return new_session_id;
end;
$$;

revoke all on function public.create_academic_session(text, date, date, smallint, boolean) from public;
grant execute on function public.create_academic_session(text, date, date, smallint, boolean) to authenticated;

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
  subject_id uuid;
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

  select s.id into subject_id
  from public.subjects s
  where lower(s.name) = lower(trim(p_subject_name))
  limit 1;

  if subject_id is null then
    insert into public.subjects (name)
    values (trim(p_subject_name))
    returning id into subject_id;
  else
    update public.subjects set is_active = true where id = subject_id;
  end if;

  insert into public.class_subject_offerings (
    class_id, subject_id, academic_session_id, is_active
  )
  values (p_class_id, subject_id, p_academic_session_id, true)
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

create or replace function public.save_result_scores(
  p_student_id uuid,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_class_subject_offering_id uuid,
  p_assessment_scheme_id uuid,
  p_term_id uuid,
  p_scores jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  result_id uuid;
  score_entry jsonb;
  score_value numeric;
  component_id uuid;
  component_max numeric;
begin
  if p_scores is null or jsonb_typeof(p_scores) is distinct from 'array' then
    raise exception 'Scores must be supplied as a list';
  end if;

  if not exists (
    select 1 from public.student_subject_results r
    where r.student_id = p_student_id
      and r.class_subject_offering_id = p_class_subject_offering_id
      and r.term_id = p_term_id
      and r.status = 'draft'
  ) then
    if not public.can_create_result(
      p_student_id, p_class_id, p_academic_session_id, p_class_subject_offering_id
    ) then
      raise exception 'Not authorized to create this result' using errcode = '42501';
    end if;

    insert into public.student_subject_results (
      student_id, class_id, academic_session_id,
      class_subject_offering_id, assessment_scheme_id, term_id, status
    )
    values (
      p_student_id, p_class_id, p_academic_session_id,
      p_class_subject_offering_id, p_assessment_scheme_id, p_term_id, 'draft'
    )
    on conflict (student_id, class_subject_offering_id, term_id) do nothing;
  end if;

  select r.id into result_id
  from public.student_subject_results r
  where r.student_id = p_student_id
    and r.class_id = p_class_id
    and r.academic_session_id = p_academic_session_id
    and r.class_subject_offering_id = p_class_subject_offering_id
    and r.assessment_scheme_id = p_assessment_scheme_id
    and r.term_id = p_term_id
    and r.status = 'draft'
  for update;

  if result_id is null then
    raise exception 'This result is not an editable draft' using errcode = '42501';
  end if;
  if not public.can_edit_result(result_id) then
    raise exception 'Not authorized to edit this result' using errcode = '42501';
  end if;

  for score_entry in select value from jsonb_array_elements(p_scores)
  loop
    component_id := (score_entry->>'assessment_component_id')::uuid;
    score_value := (score_entry->>'score')::numeric;

    select c.max_score into component_max
    from public.assessment_components c
    where c.id = component_id
      and c.assessment_scheme_id = p_assessment_scheme_id;

    if component_max is null or score_value is null
       or score_value < 0 or score_value > component_max then
      raise exception 'A score is invalid or exceeds its configured maximum';
    end if;

    insert into public.result_component_scores (
      result_id, assessment_scheme_id, assessment_component_id, score, recorded_by
    )
    values (result_id, p_assessment_scheme_id, component_id, score_value, auth.uid())
    on conflict (result_id, assessment_component_id) do update
      set score = excluded.score,
          recorded_by = excluded.recorded_by,
          updated_at = now();
  end loop;

  return result_id;
end;
$$;

revoke all on function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb) from public;
grant execute on function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb) to authenticated;
