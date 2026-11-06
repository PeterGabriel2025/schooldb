alter table public.assessment_schemes
  add column is_current boolean not null default true;

alter table public.assessment_schemes
  drop constraint if exists assessment_schemes_class_subject_offering_id_key;

create unique index assessment_schemes_one_current_per_offering
  on public.assessment_schemes (class_subject_offering_id)
  where is_current;

create table public.section_assessment_settings (
  stage public.school_stage primary key,
  components jsonb not null check (jsonb_typeof(components) = 'array'),
  updated_by uuid not null references public.profiles (id) on delete restrict,
  updated_at timestamptz not null default now()
);

alter table public.section_assessment_settings enable row level security;
revoke all on public.section_assessment_settings from anon, authenticated;
grant select on public.section_assessment_settings to authenticated;
create policy section_assessment_settings_read
  on public.section_assessment_settings
  for select to authenticated
  using (true);

revoke insert, update, delete on public.assessment_schemes,
  public.assessment_components from authenticated;
revoke insert on public.class_subject_offerings from authenticated;

revoke all on function public.configure_class_subject(uuid, uuid, text, jsonb)
  from public, authenticated;
revoke all on function public.admin_update_assessment_components(uuid, jsonb)
  from public, authenticated;

create or replace function public.admin_save_section_assessment(
  p_stage public.school_stage,
  p_components jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  component jsonb;
  normalized_components jsonb := '[]'::jsonb;
  component_code text;
  component_name text;
  component_max numeric;
  component_order integer := 0;
  component_codes text[] := array[]::text[];
  offering_record record;
  scheme_id uuid;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can configure section assessments'
      using errcode = '42501';
  end if;

  if p_stage is null then
    raise exception 'Select a school section';
  end if;
  if p_components is null or jsonb_typeof(p_components) is distinct from 'array' then
    raise exception 'Assessment components must be supplied as a list';
  end if;
  if jsonb_array_length(p_components) not between 1 and 10 then
    raise exception 'Configure between 1 and 10 assessment components';
  end if;
  if exists (
    select 1
    from public.student_subject_results r
    join public.class_subject_offerings o on o.id = r.class_subject_offering_id
    join public.classes c on c.id = o.class_id
    where c.stage = p_stage and r.status = 'draft'
  ) then
    raise exception 'Finish or remove draft results in this section before changing its assessment scheme';
  end if;

  for component in select value from jsonb_array_elements(p_components)
  loop
    component_order := component_order + 1;
    component_code := nullif(trim(component->>'code'), '');
    component_name := nullif(trim(component->>'name'), '');
    if jsonb_typeof(component) is distinct from 'object'
       or component_code is null or length(component_code) > 40
       or component_name is null or length(component_name) > 80
       or jsonb_typeof(component->'max_score') is distinct from 'number' then
      raise exception 'Each component needs a code, name, and positive maximum score';
    end if;
    component_max := (component->>'max_score')::numeric;
    if component_max <= 0 then
      raise exception 'Each component maximum score must be greater than zero';
    end if;
    if lower(component_code) = any(component_codes) then
      raise exception 'Assessment component codes must be unique within the section';
    end if;
    component_codes := array_append(component_codes, lower(component_code));
    normalized_components := normalized_components || jsonb_build_array(
      jsonb_build_object(
        'code', component_code,
        'name', component_name,
        'max_score', component_max,
        'display_order', component_order,
        'counts_toward_total', coalesce((component->>'counts_toward_total')::boolean, true),
        'is_required', coalesce((component->>'is_required')::boolean, true)
      )
    );
  end loop;

  insert into public.section_assessment_settings (stage, components, updated_by)
  values (p_stage, normalized_components, auth.uid())
  on conflict (stage) do update
    set components = excluded.components,
        updated_by = excluded.updated_by,
        updated_at = now();

  for offering_record in
    select o.id
    from public.class_subject_offerings o
    join public.classes c on c.id = o.class_id
    where c.stage = p_stage
    for update of o
  loop
    update public.assessment_schemes
    set is_current = false
    where class_subject_offering_id = offering_record.id
      and is_current;

    insert into public.assessment_schemes (
      class_subject_offering_id, name, is_current
    )
    values (
      offering_record.id,
      initcap(p_stage::text) || ' section assessment',
      true
    )
    returning id into scheme_id;

    for component in select value from jsonb_array_elements(normalized_components)
    loop
      insert into public.assessment_components (
        assessment_scheme_id, code, name, max_score, display_order,
        counts_toward_total, is_required
      )
      values (
        scheme_id,
        component->>'code',
        component->>'name',
        (component->>'max_score')::numeric,
        (component->>'display_order')::smallint,
        (component->>'counts_toward_total')::boolean,
        (component->>'is_required')::boolean
      );
    end loop;
  end loop;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_update',
    'section_assessment',
    p_stage::text,
    jsonb_build_object(
      'component_count', jsonb_array_length(normalized_components),
      'offering_count', (
        select count(*)
        from public.class_subject_offerings o
        join public.classes c on c.id = o.class_id
        where c.stage = p_stage
      )
    )
  );
end;
$$;

revoke all on function public.admin_save_section_assessment(public.school_stage, jsonb)
  from public;
grant execute on function public.admin_save_section_assessment(public.school_stage, jsonb)
  to authenticated;

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
  v_result_id uuid;
  score_entry jsonb;
  score_value numeric;
  component_id uuid;
  component_max numeric;
begin
  if p_scores is null or jsonb_typeof(p_scores) is distinct from 'array' then
    raise exception 'Scores must be supplied as a list';
  end if;

  if not exists (
    select 1
    from public.assessment_schemes s
    join public.section_assessment_settings settings on true
    join public.class_subject_offerings o on o.id = s.class_subject_offering_id
    join public.classes c on c.id = o.class_id and c.stage = settings.stage
    where s.id = p_assessment_scheme_id
      and s.class_subject_offering_id = p_class_subject_offering_id
      and s.is_current
  ) then
    raise exception 'Select the current assessment scheme configured for this school section';
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

  select r.id into v_result_id
  from public.student_subject_results r
  where r.student_id = p_student_id
    and r.class_id = p_class_id
    and r.academic_session_id = p_academic_session_id
    and r.class_subject_offering_id = p_class_subject_offering_id
    and r.assessment_scheme_id = p_assessment_scheme_id
    and r.term_id = p_term_id
    and r.status = 'draft'
  for update;

  if v_result_id is null then
    raise exception 'This result is not an editable draft' using errcode = '42501';
  end if;
  if not public.can_edit_result(v_result_id) then
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
    values (v_result_id, p_assessment_scheme_id, component_id, score_value, auth.uid())
    on conflict (result_id, assessment_component_id) do update
      set score = excluded.score,
          recorded_by = excluded.recorded_by,
          updated_at = now();
  end loop;

  return v_result_id;
end;
$$;

revoke all on function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb)
  from public;
grant execute on function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb)
  to authenticated;

create or replace function public.admin_add_subject_offering(
  p_class_id uuid,
  p_academic_session_id uuid,
  p_subject_name text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  subject_record_id uuid;
  offering_id uuid;
  scheme_id uuid;
  section_stage public.school_stage;
  section_components jsonb;
  component jsonb;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can add a subject offering'
      using errcode = '42501';
  end if;
  if p_subject_name is null or length(trim(p_subject_name)) not between 1 and 120 then
    raise exception 'Enter a valid subject name';
  end if;

  select c.stage into section_stage
  from public.classes c
  where c.id = p_class_id and c.is_active;
  if section_stage is null then
    raise exception 'Select an active class';
  end if;
  if not exists (
    select 1 from public.academic_sessions s
    where s.id = p_academic_session_id and s.is_active
  ) then
    raise exception 'Select an active academic session';
  end if;

  select settings.components into section_components
  from public.section_assessment_settings settings
  where settings.stage = section_stage;
  if section_components is null then
    raise exception 'Configure the section-wide assessment scheme before adding subjects';
  end if;

  select s.id into subject_record_id
  from public.subjects s
  where lower(s.name) = lower(trim(p_subject_name))
  limit 1;
  if subject_record_id is null then
    insert into public.subjects (name)
    values (trim(p_subject_name))
    returning id into subject_record_id;
  else
    update public.subjects set is_active = true where id = subject_record_id;
  end if;

  insert into public.class_subject_offerings (
    class_id, subject_id, academic_session_id, is_active
  )
  values (p_class_id, subject_record_id, p_academic_session_id, true)
  on conflict (class_id, subject_id, academic_session_id) do update
    set is_active = true
  returning id into offering_id;

  if exists (
    select 1 from public.assessment_schemes s
    where s.class_subject_offering_id = offering_id and s.is_current
  ) then
    return offering_id;
  end if;

  insert into public.assessment_schemes (
    class_subject_offering_id, name, is_current
  )
  values (
    offering_id,
    initcap(section_stage::text) || ' section assessment',
    true
  )
  returning id into scheme_id;

  for component in select value from jsonb_array_elements(section_components)
  loop
    insert into public.assessment_components (
      assessment_scheme_id, code, name, max_score, display_order,
      counts_toward_total, is_required
    )
    values (
      scheme_id,
      component->>'code',
      component->>'name',
      (component->>'max_score')::numeric,
      (component->>'display_order')::smallint,
      (component->>'counts_toward_total')::boolean,
      (component->>'is_required')::boolean
    );
  end loop;

  return offering_id;
end;
$$;

revoke all on function public.admin_add_subject_offering(uuid, uuid, text)
  from public;
grant execute on function public.admin_add_subject_offering(uuid, uuid, text)
  to authenticated;

create or replace function public.guard_section_result_scheme()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1
    from public.assessment_schemes s
    join public.class_subject_offerings o on o.id = s.class_subject_offering_id
    join public.classes c on c.id = o.class_id
    join public.section_assessment_settings settings on settings.stage = c.stage
    where s.id = new.assessment_scheme_id
      and s.class_subject_offering_id = new.class_subject_offering_id
      and s.is_current
  ) then
    raise exception 'Results must use the current assessment scheme configured for their school section';
  end if;
  return new;
end;
$$;

create trigger student_results_require_current_section_scheme
before insert on public.student_subject_results
for each row execute function public.guard_section_result_scheme();

create or replace function public.guard_class_section_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.stage is distinct from old.stage and exists (
    select 1 from public.class_subject_offerings o where o.class_id = old.id
  ) then
    raise exception 'A class section cannot be changed after subjects have been configured; create a class in the correct section instead';
  end if;
  return new;
end;
$$;

create trigger classes_preserve_section_after_offerings
before update of stage on public.classes
for each row execute function public.guard_class_section_change();

create or replace function public.admin_remove_subject_offering(p_offering_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  offering_record public.class_subject_offerings%rowtype;
  subject_name text;
  has_results boolean;
  outcome text;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can remove subject offerings'
      using errcode = '42501';
  end if;

  select * into offering_record
  from public.class_subject_offerings
  where id = p_offering_id
  for update;
  if not found then
    raise exception 'Subject offering not found';
  end if;

  select name into subject_name
  from public.subjects
  where id = offering_record.subject_id;

  select exists (
    select 1 from public.student_subject_results
    where class_subject_offering_id = p_offering_id
  ) into has_results;

  if has_results then
    update public.class_subject_offerings set is_active = false where id = p_offering_id;
    outcome := 'archived';
  else
    delete from public.subject_teacher_assignments
    where class_subject_offering_id = p_offering_id;
    delete from public.assessment_components c
    using public.assessment_schemes s
    where c.assessment_scheme_id = s.id
      and s.class_subject_offering_id = p_offering_id;
    delete from public.assessment_schemes
    where class_subject_offering_id = p_offering_id;
    delete from public.class_subject_offerings where id = p_offering_id;

    if not exists (
      select 1 from public.class_subject_offerings
      where subject_id = offering_record.subject_id
    ) then
      delete from public.subjects where id = offering_record.subject_id;
      outcome := 'deleted';
    else
      outcome := 'deleted_offering';
    end if;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_' || outcome,
    'class_subject_offering',
    p_offering_id::text,
    jsonb_build_object('subject', subject_name, 'class_id', offering_record.class_id)
  );
  return outcome;
end;
$$;

revoke all on function public.admin_remove_subject_offering(uuid) from public;
grant execute on function public.admin_remove_subject_offering(uuid) to authenticated;
