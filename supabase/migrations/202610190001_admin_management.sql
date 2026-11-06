drop policy if exists profiles_update_self_or_admin on public.profiles;
create policy profiles_update_admin on public.profiles
for update to authenticated
using (public.is_active_administrator())
with check (public.is_active_administrator());

create or replace function public.prevent_removing_last_administrator()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.role = 'administrator'
     and old.is_active
     and (new.role <> 'administrator' or not new.is_active)
     and (
       select count(*) from public.profiles
       where role = 'administrator' and is_active
     ) <= 1 then
    raise exception 'The last active administrator cannot be deactivated or demoted';
  end if;
  return new;
end;
$$;

create trigger profiles_keep_active_administrator
before update on public.profiles
for each row execute function public.prevent_removing_last_administrator();

alter table public.academic_sessions
  add column is_active boolean not null default true;

create or replace function public.complete_password_setup()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in before completing password setup' using errcode = '42501';
  end if;
  update public.profiles
  set must_change_password = false
  where id = auth.uid() and is_active;
  if not found then
    raise exception 'An active school profile is required to complete password setup'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.complete_password_setup() from public;
grant execute on function public.complete_password_setup() to authenticated;

create or replace function public.admin_update_academic_session(
  p_session_id uuid,
  p_name text,
  p_starts_on date,
  p_ends_on date,
  p_active_term smallint,
  p_make_current boolean
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can edit academic sessions'
      using errcode = '42501';
  end if;
  if p_name is null or length(trim(p_name)) not between 4 and 20
     or p_starts_on is null or p_ends_on is null or p_starts_on >= p_ends_on
     or p_active_term is null or p_active_term not between 1 and 3
     or p_make_current is null then
    raise exception 'Enter a valid session name, date range, and active term';
  end if;
  if not exists (select 1 from public.academic_sessions where id = p_session_id) then
    raise exception 'Academic session not found';
  end if;
  if p_make_current and not exists (
    select 1 from public.academic_sessions
    where id = p_session_id and is_active
  ) then
    raise exception 'Restore the academic session before making it current';
  end if;
  if p_make_current then
    update public.academic_sessions
    set is_current = false
    where is_current and id <> p_session_id;
  end if;
  update public.academic_sessions
  set name = trim(p_name),
      starts_on = p_starts_on,
      ends_on = p_ends_on,
      is_current = p_make_current
  where id = p_session_id;
  update public.terms
  set is_active = (term_number = p_active_term)
  where academic_session_id = p_session_id;
end;
$$;

revoke all on function public.admin_update_academic_session(uuid, text, date, date, smallint, boolean) from public;
grant execute on function public.admin_update_academic_session(uuid, text, date, date, smallint, boolean) to authenticated;

create or replace function public.admin_remove_academic_session(p_session_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  session_record public.academic_sessions%rowtype;
  has_history boolean;
  outcome text;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can remove academic sessions'
      using errcode = '42501';
  end if;
  select * into session_record
  from public.academic_sessions
  where id = p_session_id
  for update;
  if not found then
    raise exception 'Academic session not found';
  end if;

  select exists (
    select 1 from public.class_enrollments where academic_session_id = p_session_id
    union all
    select 1 from public.class_subject_offerings where academic_session_id = p_session_id
    union all
    select 1 from public.class_teacher_assignments where academic_session_id = p_session_id
  ) into has_history;

  if has_history then
    update public.academic_sessions
    set is_active = false, is_current = false
    where id = p_session_id;
    outcome := 'archived';
  else
    delete from public.terms where academic_session_id = p_session_id;
    delete from public.academic_sessions where id = p_session_id;
    outcome := 'deleted';
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_' || outcome,
    'academic_session',
    p_session_id::text,
    jsonb_build_object('name', session_record.name)
  );
  return outcome;
end;
$$;

revoke all on function public.admin_remove_academic_session(uuid) from public;
grant execute on function public.admin_remove_academic_session(uuid) to authenticated;

create or replace function public.admin_deactivate_teacher(p_teacher_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can deactivate teacher accounts'
      using errcode = '42501';
  end if;
  update public.profiles
  set is_active = false
  where id = p_teacher_id and role <> 'administrator';
  if not found then
    raise exception 'Teacher account not found';
  end if;
end;
$$;

revoke all on function public.admin_deactivate_teacher(uuid) from public;
grant execute on function public.admin_deactivate_teacher(uuid) to authenticated;

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
    join public.classes c on c.id = r.class_id
    join public.profiles p on p.id = auth.uid() and p.is_active
    where r.id = p_result_id
      and r.status = 'draft'
      and o.is_active
      and c.is_active
      and not public.is_scoped_permission_denied('results.edit', r.class_id, o.subject_id, r.academic_session_id)
      and (
        (p.role = 'administrator' and p.is_active)
        or public.has_scoped_permission('results.edit', r.class_id, o.subject_id, r.academic_session_id)
        or (
          p.role in ('primary_teacher', 'nursery_teacher')
          and exists (
            select 1 from public.class_teacher_assignments a
            where a.teacher_id = auth.uid()
              and a.class_id = r.class_id
              and a.academic_session_id = r.academic_session_id
          )
        )
        or exists (
          select 1 from public.subject_teacher_assignments a
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
  select exists (
    select 1
    from public.class_subject_offerings o
    join public.classes c on c.id = o.class_id
    join public.profiles p on p.id = auth.uid() and p.is_active
    where o.id = p_class_subject_offering_id
      and o.class_id = p_class_id
      and o.academic_session_id = p_academic_session_id
      and o.is_active
      and c.is_active
      and exists (
        select 1 from public.class_enrollments e
        where e.student_id = p_student_id
          and e.class_id = p_class_id
          and e.academic_session_id = p_academic_session_id
      )
      and (
        p.role = 'administrator'
        or (
          not public.is_scoped_permission_denied('results.edit', p_class_id, o.subject_id, p_academic_session_id)
          and (
            public.has_scoped_permission('results.edit', p_class_id, o.subject_id, p_academic_session_id)
            or (
              p.role in ('primary_teacher', 'nursery_teacher')
              and exists (
                select 1 from public.class_teacher_assignments a
                where a.teacher_id = auth.uid()
                  and a.class_id = p_class_id
                  and a.academic_session_id = p_academic_session_id
              )
            )
            or exists (
              select 1 from public.subject_teacher_assignments a
              where a.teacher_id = auth.uid()
                and a.class_subject_offering_id = o.id
            )
          )
        )
      )
  );
$$;

create or replace function public.get_class_standings(
  p_class_id uuid,
  p_academic_session_id uuid,
  p_term_id uuid
)
returns table (
  student_id uuid,
  admission_number text,
  student_name text,
  grand_total numeric,
  average_score numeric,
  "position" bigint,
  is_complete boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.can_view_class_results(p_class_id, p_academic_session_id) then
    raise exception 'Not authorized to view class results' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.terms t
    where t.id = p_term_id
      and t.academic_session_id = p_academic_session_id
  ) then
    raise exception 'Term does not belong to the selected academic session';
  end if;

  return query
  with expected_subjects as (
    select o.id, o.counts_toward_total, o.counts_toward_average
    from public.class_subject_offerings o
    where o.class_id = p_class_id
      and o.academic_session_id = p_academic_session_id
      and (
        o.is_active
        or exists (
          select 1
          from public.student_subject_results historical_result
          where historical_result.class_subject_offering_id = o.id
            and historical_result.term_id = p_term_id
        )
      )
  ),
  subject_calculations as (
    select
      e.student_id,
      es.id as offering_id,
      es.counts_toward_total,
      es.counts_toward_average,
      r.id as result_id,
      r.assessment_scheme_id,
      count(c.id) filter (where c.is_required) as required_count,
      count(c.id) filter (where c.is_required and s.id is not null) as entered_required_count,
      sum(s.score) filter (
        where c.counts_toward_total and s.id is not null
      ) as subject_total
    from public.class_enrollments e
    cross join expected_subjects es
    left join public.student_subject_results r
      on r.student_id = e.student_id
     and r.class_subject_offering_id = es.id
     and r.term_id = p_term_id
    left join public.assessment_components c
      on c.assessment_scheme_id = r.assessment_scheme_id
    left join public.result_component_scores s
      on s.result_id = r.id
     and s.assessment_component_id = c.id
    where e.class_id = p_class_id
      and e.academic_session_id = p_academic_session_id
    group by e.student_id, es.id, es.counts_toward_total,
      es.counts_toward_average, r.id, r.assessment_scheme_id
  ),
  student_summaries as (
    select
      sc.student_id,
      sum(sc.subject_total) filter (
        where sc.counts_toward_total
          and sc.required_count > 0
          and sc.required_count = sc.entered_required_count
          and sc.result_id is not null
          and sc.subject_total is not null
      ) as calculated_total,
      sum(sc.subject_total) filter (
        where sc.counts_toward_average
          and sc.required_count > 0
          and sc.required_count = sc.entered_required_count
          and sc.result_id is not null
          and sc.subject_total is not null
      ) as calculated_average_total,
      count(*) filter (
        where sc.counts_toward_total
          and (
            sc.result_id is null
              or sc.required_count = 0
              or sc.required_count <> sc.entered_required_count
              or sc.subject_total is null
          )
      ) = 0 as totals_complete,
      count(*) filter (where sc.counts_toward_average) as average_subject_count,
      count(*) filter (where sc.counts_toward_total) as total_subject_count,
      count(*) filter (
        where sc.counts_toward_average
          and (
            sc.result_id is null
              or sc.required_count = 0
              or sc.required_count <> sc.entered_required_count
              or sc.subject_total is null
          )
      ) = 0 as average_subjects_complete
    from subject_calculations sc
    group by sc.student_id
  ),
  ranked as (
    select
      ss.student_id,
      case
        when ss.totals_complete and ss.total_subject_count > 0
        then coalesce(ss.calculated_total, 0)
      end as total_score,
      case
        when ss.totals_complete
         and ss.total_subject_count > 0
         and ss.average_subjects_complete
         and ss.average_subject_count > 0
        then coalesce(ss.calculated_average_total, 0) / ss.average_subject_count
      end as average_value,
      ss.totals_complete
        and ss.total_subject_count > 0
        and ss.average_subjects_complete
        and ss.average_subject_count > 0 as complete
    from student_summaries ss
  ),
  positioned as (
    select
      r.student_id,
      r.total_score,
      r.average_value,
      r.complete,
      case when r.complete then
        rank() over (
          order by case when r.complete then r.average_value end desc nulls last
        )
      end as rank_position
    from ranked r
  )
  select
    p.student_id,
    s.admission_number,
    trim(concat_ws(' ', s.first_name, s.other_names, s.last_name)),
    p.total_score,
    p.average_value,
    p.rank_position,
    p.complete
  from positioned p
  join public.students s on s.id = p.student_id
  order by p.average_value desc nulls last, s.last_name, s.first_name;
end;
$$;

create or replace function public.admin_remove_class(p_class_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  class_record public.classes%rowtype;
  has_history boolean;
  outcome text;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can remove classes'
      using errcode = '42501';
  end if;

  select * into class_record
  from public.classes
  where id = p_class_id
  for update;

  if not found then
    raise exception 'Class not found';
  end if;

  select exists (
    select 1 from public.class_enrollments where class_id = p_class_id
    union all
    select 1 from public.class_teacher_assignments where class_id = p_class_id
    union all
    select 1 from public.class_subject_offerings where class_id = p_class_id
  ) into has_history;

  if has_history then
    update public.classes set is_active = false where id = p_class_id;
    outcome := 'archived';
  else
    delete from public.classes where id = p_class_id;
    outcome := 'deleted';
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_' || outcome,
    'class',
    p_class_id::text,
    jsonb_build_object('name', class_record.name, 'stage', class_record.stage)
  );
  return outcome;
end;
$$;

revoke all on function public.admin_remove_class(uuid) from public;
grant execute on function public.admin_remove_class(uuid) to authenticated;

create or replace function public.admin_remove_subject_offering(p_offering_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  offering_record public.class_subject_offerings%rowtype;
  scheme_id uuid;
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

  select id into scheme_id
  from public.assessment_schemes
  where class_subject_offering_id = p_offering_id;

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
    if scheme_id is not null then
      delete from public.assessment_components where assessment_scheme_id = scheme_id;
      delete from public.assessment_schemes where id = scheme_id;
    end if;
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

create or replace function public.admin_update_assessment_components(
  p_offering_id uuid,
  p_components jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  component jsonb;
  component_id uuid;
  new_max_score numeric;
  new_component_name text;
  expected_count integer;
  supplied_count integer;
  distinct_count integer;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can edit assessment schemes'
      using errcode = '42501';
  end if;
  if p_components is null or jsonb_typeof(p_components) is distinct from 'array' then
    raise exception 'Assessment components must be supplied as a list';
  end if;
  if not exists (
    select 1 from public.class_subject_offerings
    where id = p_offering_id
  ) then
    raise exception 'Subject offering not found';
  end if;

  select count(*) into expected_count
  from public.assessment_components c
  join public.assessment_schemes s on s.id = c.assessment_scheme_id
  where s.class_subject_offering_id = p_offering_id;
  supplied_count := jsonb_array_length(p_components);
  select count(distinct (value->>'id')) into distinct_count
  from jsonb_array_elements(p_components);
  if expected_count = 0 or supplied_count <> expected_count or distinct_count <> supplied_count then
    raise exception 'Provide an updated value for every component in the assessment scheme';
  end if;

  for component in select value from jsonb_array_elements(p_components)
  loop
    component_id := (component->>'id')::uuid;
    new_component_name := nullif(trim(component->>'name'), '');
    new_max_score := nullif(component->>'max_score', '')::numeric;
    if new_component_name is null or new_max_score is null or new_max_score <= 0 then
      raise exception 'Each assessment component needs a name and positive maximum score';
    end if;
    if not exists (
      select 1
      from public.assessment_components c
      join public.assessment_schemes s on s.id = c.assessment_scheme_id
      where c.id = component_id
        and s.class_subject_offering_id = p_offering_id
    ) then
      raise exception 'An assessment component does not belong to the selected subject';
    end if;
    if exists (
      select 1
      from public.result_component_scores score
      where score.assessment_component_id = component_id
        and score.score > new_max_score
    ) then
      raise exception 'A saved score exceeds the new maximum for component %', new_component_name;
    end if;

    update public.assessment_components
    set name = new_component_name,
        max_score = new_max_score
    where id = component_id;
  end loop;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_update',
    'assessment_scheme',
    p_offering_id::text,
    jsonb_build_object('component_count', supplied_count)
  );
end;
$$;

revoke all on function public.admin_update_assessment_components(uuid, jsonb) from public;
grant execute on function public.admin_update_assessment_components(uuid, jsonb) to authenticated;

create or replace function public.admin_save_grading_scale(
  p_name text,
  p_bands jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  scale_id uuid;
  band jsonb;
  band_count integer;
  band_minimum numeric;
  band_maximum numeric;
  band_grade text;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can edit the grading scale'
      using errcode = '42501';
  end if;
  if p_name is null or length(trim(p_name)) not between 1 and 120 then
    raise exception 'Enter a valid grading scale name';
  end if;
  if p_bands is null or jsonb_typeof(p_bands) is distinct from 'array' then
    raise exception 'Grading bands must be supplied as a list';
  end if;
  band_count := jsonb_array_length(p_bands);
  if band_count < 1 or band_count > 20 then
    raise exception 'Configure between 1 and 20 grading bands';
  end if;

  select id into scale_id
  from public.grading_scales
  where is_active
  for update;
  if scale_id is null then
    select id into scale_id
    from public.grading_scales
    where name = trim(p_name)
    limit 1
    for update;
    if scale_id is null then
      insert into public.grading_scales (name, is_active)
      values (trim(p_name), true)
      returning id into scale_id;
    else
      update public.grading_scales set is_active = true where id = scale_id;
    end if;
  else
    update public.grading_scales
    set name = trim(p_name)
    where id = scale_id;
  end if;

  delete from public.grading_bands where grading_scale_id = scale_id;
  for band in select value from jsonb_array_elements(p_bands)
  loop
    band_grade := nullif(trim(band->>'grade'), '');
    band_minimum := nullif(band->>'minimum_score', '')::numeric;
    band_maximum := nullif(band->>'maximum_score', '')::numeric;
    if band_grade is null or length(band_grade) > 12
       or band_minimum is null or band_maximum is null
       or band_minimum < 0 or band_maximum < band_minimum then
      raise exception 'Each grading band needs a grade and a valid score range';
    end if;
    insert into public.grading_bands (grading_scale_id, grade, minimum_score, maximum_score, remark)
    values (
      scale_id,
      band_grade,
      band_minimum,
      band_maximum,
      nullif(trim(band->>'remark'), '')
    );
  end loop;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_update',
    'grading_scale',
    scale_id::text,
    jsonb_build_object('name', trim(p_name), 'band_count', band_count)
  );
  return scale_id;
end;
$$;

revoke all on function public.admin_save_grading_scale(text, jsonb) from public;
grant execute on function public.admin_save_grading_scale(text, jsonb) to authenticated;
