alter table public.class_enrollments
  add column division text check (division in ('science', 'arts'));

alter table public.class_subject_offerings
  add column senior_secondary_group text
    check (senior_secondary_group in ('core', 'science', 'arts', 'optional')),
  add column senior_secondary_eligible_streams text[] not null default '{}'
    check (senior_secondary_eligible_streams <@ array['science', 'arts']::text[]);

update public.class_subject_offerings o
set senior_secondary_group = case
      when normalized.name ~ '^(MATHS|MATHEMATICS|ENGLISH|ENGLISH STUDIES|ENGLISH LANGUAGE|ECONOMICS|CIVIC|CIVIC EDUCATION|BIOLOGY)$' then 'core'
      when normalized.name ~ '^(GOVERNMENT|GOVT|LITERATURE|LITERATURE-IN-ENGLISH|LITERATURE IN ENGLISH|CRS|CHRISTIAN RELIGIOUS STUDIES)$' then 'arts'
      when normalized.name ~ '^(CHEMISTRY|PHYSICS)$' then 'science'
      when normalized.name ~ '^(IGBO|ASUSU IGBO|MARKETING|DATA PROCESSING|AGRICULTURAL SCIENCE|AGRICULTURE|GEOGRAPHY)$' then 'optional'
      else null
    end,
    senior_secondary_eligible_streams = case
      when normalized.name ~ '^(MATHS|MATHEMATICS|ENGLISH|ENGLISH STUDIES|ENGLISH LANGUAGE|ECONOMICS|CIVIC|CIVIC EDUCATION|BIOLOGY)$'
        then array['science', 'arts']::text[]
      when normalized.name ~ '^(GOVERNMENT|GOVT|LITERATURE|LITERATURE-IN-ENGLISH|LITERATURE IN ENGLISH|CRS|CHRISTIAN RELIGIOUS STUDIES)$'
        then array['arts']::text[]
      when normalized.name ~ '^(CHEMISTRY|PHYSICS)$'
        then array['science']::text[]
      when normalized.name ~ '^(IGBO|ASUSU IGBO|MARKETING|DATA PROCESSING|AGRICULTURAL SCIENCE|AGRICULTURE|GEOGRAPHY)$'
        then array['science', 'arts']::text[]
      else '{}'::text[]
    end
from (
  select o.id, upper(regexp_replace(trim(s.name), '[[:space:]]+', ' ', 'g')) as name
  from public.class_subject_offerings o
  join public.subjects s on s.id = o.subject_id
  join public.classes c on c.id = o.class_id
  where regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
    ~ '^SSS[[:space:]]*[23]([^0-9].*)?$'
) normalized
where o.id = normalized.id;

create table public.student_subject_selections (
  student_id uuid not null,
  class_id uuid not null,
  academic_session_id uuid not null,
  class_subject_offering_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (student_id, class_subject_offering_id),
  foreign key (student_id, class_id, academic_session_id)
    references public.class_enrollments (student_id, class_id, academic_session_id)
    on delete cascade,
  foreign key (class_subject_offering_id, class_id, academic_session_id)
    references public.class_subject_offerings (id, class_id, academic_session_id)
    on delete cascade
);

alter table public.student_subject_selections enable row level security;

create policy student_subject_selections_read_assigned
on public.student_subject_selections
for select to authenticated
using (public.can_access_class_session(class_id, academic_session_id));

grant select on public.student_subject_selections to authenticated;

create or replace function public.validate_senior_secondary_enrollment_division()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  class_name text;
  selected_count integer;
  core_count integer;
  stream_subject_count integer;
  optional_count integer;
  eligible_count integer;
begin
  if new.division is null then
    return new;
  end if;

  select regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
  into class_name
  from public.classes c
  where c.id = new.class_id;

  if class_name !~ '^SSS[[:space:]]*[23]([^0-9].*)?$' then
    raise exception 'Science and Arts divisions are only available in SSS 2 and SSS 3';
  end if;

  select count(*),
    count(*) filter (where o.senior_secondary_group = 'core'),
    count(*) filter (where o.senior_secondary_group = new.division),
    count(*) filter (where o.senior_secondary_group = 'optional'),
    count(*) filter (where new.division = any(o.senior_secondary_eligible_streams)
      and o.counts_toward_average)
  into selected_count, core_count, stream_subject_count, optional_count, eligible_count
  from public.student_subject_selections selection
  join public.class_subject_offerings o
    on o.id = selection.class_subject_offering_id
  where selection.student_id = new.student_id
    and selection.class_id = new.class_id
    and selection.academic_session_id = new.academic_session_id;

  if selected_count <> 9 or core_count <> 5
     or stream_subject_count <> (case when new.division = 'arts' then 3 else 2 end)
     or optional_count <> (case when new.division = 'arts' then 1 else 2 end)
     or eligible_count <> 9 then
    raise exception 'Select the 5 general subjects, all required stream subjects, and the correct number of optional subjects';
  end if;

  return new;
end;
$$;

create trigger class_enrollments_validate_senior_division
before insert or update of division on public.class_enrollments
for each row execute function public.validate_senior_secondary_enrollment_division();

create or replace function public.save_senior_secondary_subjects(
  p_student_id uuid,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_division text,
  p_offering_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  class_name text;
  previous_offering_ids uuid[];
  requested_offering_ids uuid[];
  previous_division text;
  valid_count integer;
  core_count integer;
  stream_subject_count integer;
  optional_count integer;
begin
  if not public.can_manage_class_register(p_class_id, p_academic_session_id) then
    raise exception 'Not authorized to manage this class register' using errcode = '42501';
  end if;
  if p_division not in ('science', 'arts') then
    raise exception 'Choose Science or Arts for this student';
  end if;

  select regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
  into class_name
  from public.classes c
  where c.id = p_class_id and c.stage = 'secondary' and c.is_active;
  if class_name is null or class_name !~ '^SSS[[:space:]]*[23]([^0-9].*)?$' then
    raise exception 'Science and Arts divisions are only available in SSS 2 and SSS 3';
  end if;
  if not exists (
    select 1 from public.class_enrollments e
    where e.student_id = p_student_id
      and e.class_id = p_class_id
      and e.academic_session_id = p_academic_session_id
      and e.left_on is null
  ) then
    raise exception 'Student is not actively enrolled in this SSS class and session';
  end if;
  if coalesce(cardinality(p_offering_ids), 0) <> 9
     or (select count(distinct requested.offering_id)
         from unnest(p_offering_ids) as requested(offering_id)) <> 9 then
    raise exception 'Choose exactly 9 subjects for this student';
  end if;

  select count(*),
    count(*) filter (where o.senior_secondary_group = 'core'),
    count(*) filter (where o.senior_secondary_group = p_division),
    count(*) filter (where o.senior_secondary_group = 'optional')
  into valid_count, core_count, stream_subject_count, optional_count
  from unnest(p_offering_ids) requested(offering_id)
  join public.class_subject_offerings o
    on o.id = requested.offering_id
   and o.class_id = p_class_id
   and o.academic_session_id = p_academic_session_id
   and o.is_active
   and o.counts_toward_total
   and o.counts_toward_average
   and p_division = any(o.senior_secondary_eligible_streams);
  if valid_count <> 9 or core_count <> 5
     or stream_subject_count <> (case when p_division = 'arts' then 3 else 2 end)
     or optional_count <> (case when p_division = 'arts' then 1 else 2 end) then
    raise exception 'Select the 5 general subjects, all required stream subjects, and the correct number of optional subjects';
  end if;

  select coalesce(array_agg(selection.class_subject_offering_id order by selection.class_subject_offering_id),
    '{}'::uuid[])
  into previous_offering_ids
  from public.student_subject_selections selection
  where selection.student_id = p_student_id
    and selection.class_id = p_class_id
    and selection.academic_session_id = p_academic_session_id;
  select array_agg(requested.offering_id order by requested.offering_id)
  into requested_offering_ids
  from unnest(p_offering_ids) as requested(offering_id);
  select e.division into previous_division
  from public.class_enrollments e
  where e.student_id = p_student_id
    and e.class_id = p_class_id
    and e.academic_session_id = p_academic_session_id;

  if cardinality(previous_offering_ids) > 0
     and (previous_offering_ids is distinct from requested_offering_ids
       or previous_division is distinct from p_division)
     and exists (
       select 1 from public.student_subject_results r
       where r.student_id = p_student_id
         and r.class_id = p_class_id
         and r.academic_session_id = p_academic_session_id
     ) then
    raise exception 'Subject choices cannot be changed after results have been saved';
  end if;

  delete from public.student_subject_selections
  where student_id = p_student_id
    and class_id = p_class_id
    and academic_session_id = p_academic_session_id;
  insert into public.student_subject_selections (
    student_id, class_id, academic_session_id, class_subject_offering_id
  )
  select p_student_id, p_class_id, p_academic_session_id, requested.offering_id
  from unnest(p_offering_ids) as requested(offering_id);

  update public.class_enrollments
  set division = p_division
  where student_id = p_student_id
    and class_id = p_class_id
    and academic_session_id = p_academic_session_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'update',
    'student_stream',
    p_student_id::text,
    jsonb_build_object(
      'class_id', p_class_id,
      'academic_session_id', p_academic_session_id,
      'division', p_division,
      'subject_count', 9
    )
  );
end;
$$;

revoke all on function public.save_senior_secondary_subjects(uuid, uuid, uuid, text, uuid[])
  from public, anon, authenticated;

create or replace function public.register_student_with_stream(
  p_admission_number text,
  p_first_name text,
  p_last_name text,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_other_names text,
  p_gender text,
  p_date_of_birth date,
  p_division text,
  p_offering_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_student_id uuid;
begin
  new_student_id := public.register_student(
    p_admission_number, p_first_name, p_last_name, p_class_id,
    p_academic_session_id, p_other_names, p_gender, p_date_of_birth
  );
  perform public.save_senior_secondary_subjects(
    new_student_id, p_class_id, p_academic_session_id, p_division, p_offering_ids
  );
  return new_student_id;
end;
$$;

create or replace function public.update_registered_student_with_stream(
  p_student_id uuid,
  p_admission_number text,
  p_first_name text,
  p_last_name text,
  p_other_names text,
  p_gender text,
  p_date_of_birth date,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_division text,
  p_offering_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.update_registered_student(
    p_student_id, p_admission_number, p_first_name, p_last_name,
    p_other_names, p_gender, p_date_of_birth
  );
  perform public.save_senior_secondary_subjects(
    p_student_id, p_class_id, p_academic_session_id, p_division, p_offering_ids
  );
end;
$$;

revoke all on function public.register_student_with_stream(text, text, text, uuid, uuid, text, text, date, text, uuid[])
  from public, anon;
revoke all on function public.update_registered_student_with_stream(uuid, text, text, text, text, text, date, uuid, uuid, text, uuid[])
  from public, anon;
grant execute on function public.register_student_with_stream(text, text, text, uuid, uuid, text, text, date, text, uuid[])
  to authenticated;
grant execute on function public.update_registered_student_with_stream(uuid, text, text, text, text, text, date, uuid, uuid, text, uuid[])
  to authenticated;

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
      and (
        not regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
          ~ '^SSS[[:space:]]*[23]([^0-9].*)?$'
        or exists (
          select 1 from public.student_subject_selections selection
          where selection.student_id = r.student_id
            and selection.class_id = r.class_id
            and selection.academic_session_id = r.academic_session_id
            and selection.class_subject_offering_id = o.id
        )
      )
      and not public.is_scoped_permission_denied('results.edit', r.class_id, o.subject_id, r.academic_session_id)
      and (
        (p.role = 'administrator' and p.is_active)
        or public.has_scoped_permission('results.edit', r.class_id, o.subject_id, r.academic_session_id)
        or exists (
          select 1
          from public.subject_teacher_assignments a
          where a.teacher_id = auth.uid()
            and a.class_subject_offering_id = r.class_subject_offering_id
            and a.term_id = r.term_id
        )
      )
  );
$$;

revoke all on function public.can_edit_result(uuid) from public;
grant execute on function public.can_edit_result(uuid) to authenticated;

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
    where o.id = p_class_subject_offering_id
      and o.class_id = p_class_id
      and o.academic_session_id = p_academic_session_id
      and exists (
        select 1 from public.class_enrollments e
        where e.student_id = p_student_id
          and e.class_id = p_class_id
          and e.academic_session_id = p_academic_session_id
      )
      and (
        not regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
          ~ '^SSS[[:space:]]*[23]([^0-9].*)?$'
        or exists (
          select 1 from public.student_subject_selections selection
          where selection.student_id = p_student_id
            and selection.class_id = p_class_id
            and selection.academic_session_id = p_academic_session_id
            and selection.class_subject_offering_id = o.id
        )
      )
      and (
        public.is_active_administrator()
        or (
          not public.is_scoped_permission_denied('results.edit', p_class_id, o.subject_id, p_academic_session_id)
          and exists (
            select 1
            from public.profiles p
            join public.terms t on t.academic_session_id = p_academic_session_id
              and t.is_active
            where p.id = auth.uid()
              and p.is_active
              and (
                public.has_scoped_permission('results.edit', p_class_id, o.subject_id, p_academic_session_id)
                or exists (
                  select 1 from public.subject_teacher_assignments a
                  where a.teacher_id = auth.uid()
                    and a.class_subject_offering_id = o.id
                    and a.term_id = t.id
                )
              )
          )
        )
      )
  );
$$;

revoke all on function public.can_create_result(uuid, uuid, uuid, uuid) from public;
grant execute on function public.can_create_result(uuid, uuid, uuid, uuid) to authenticated;

drop function public.get_class_standings(uuid, uuid, uuid);

create function public.get_class_standings(
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
  is_complete boolean,
  division text
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
    where t.id = p_term_id and t.academic_session_id = p_academic_session_id
  ) then
    raise exception 'Term does not belong to the selected academic session';
  end if;

  return query
  with target_class as (
    select regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
      ~ '^SSS[[:space:]]*[23]([^0-9].*)?$' as is_stream_class
    from public.classes c
    where c.id = p_class_id
  ),
  expected_subjects as (
    select e.student_id, o.id, o.counts_toward_total, o.counts_toward_average
    from public.class_enrollments e
    cross join target_class tc
    join public.class_subject_offerings o
      on o.class_id = e.class_id
     and o.academic_session_id = e.academic_session_id
    where e.class_id = p_class_id
      and e.academic_session_id = p_academic_session_id
      and not tc.is_stream_class
      and (
        o.is_active
        or exists (
          select 1 from public.student_subject_results historical_result
          where historical_result.class_subject_offering_id = o.id
            and historical_result.term_id = p_term_id
        )
      )
    union all
    select e.student_id, o.id, o.counts_toward_total, o.counts_toward_average
    from public.class_enrollments e
    join target_class tc on tc.is_stream_class
    join public.student_subject_selections selection
      on selection.student_id = e.student_id
     and selection.class_id = e.class_id
     and selection.academic_session_id = e.academic_session_id
    join public.class_subject_offerings o
      on o.id = selection.class_subject_offering_id
     and o.class_id = e.class_id
     and o.academic_session_id = e.academic_session_id
    where e.class_id = p_class_id
      and e.academic_session_id = p_academic_session_id
  ),
  subject_calculations as (
    select
      es.student_id,
      es.id as offering_id,
      es.counts_toward_total,
      es.counts_toward_average,
      e.division,
      r.id as result_id,
      r.assessment_scheme_id,
      count(c.id) filter (where c.is_required) as required_count,
      count(c.id) filter (where c.is_required and s.id is not null) as entered_required_count,
      sum(s.score) filter (where c.counts_toward_total and s.id is not null) as subject_total
    from expected_subjects es
    join public.class_enrollments e
      on e.student_id = es.student_id
     and e.class_id = p_class_id
     and e.academic_session_id = p_academic_session_id
    left join public.student_subject_results r
      on r.student_id = es.student_id
     and r.class_subject_offering_id = es.id
     and r.term_id = p_term_id
    left join public.assessment_components c on c.assessment_scheme_id = r.assessment_scheme_id
    left join public.result_component_scores s
      on s.result_id = r.id and s.assessment_component_id = c.id
    group by es.student_id, es.id, es.counts_toward_total,
      es.counts_toward_average, e.division, r.id, r.assessment_scheme_id
  ),
  student_summaries as (
    select
      e.student_id,
      e.division,
      tc.is_stream_class,
      coalesce(sum(sc.subject_total) filter (
        where sc.counts_toward_total and sc.required_count > 0
          and sc.required_count = sc.entered_required_count
          and sc.result_id is not null and sc.subject_total is not null
      ), 0) as calculated_total,
      coalesce(sum(
        sc.subject_total / case
          when exists (select 1 from public.classes c where c.id = p_class_id and c.stage in ('primary', 'nursery'))
          then sc.required_count else 1 end
      ) filter (
        where sc.counts_toward_average and sc.required_count > 0
          and sc.required_count = sc.entered_required_count
          and sc.result_id is not null and sc.subject_total is not null
      ), 0) as calculated_average_total,
      count(*) filter (
        where sc.counts_toward_total and (
          sc.result_id is null or sc.required_count = 0
          or sc.required_count <> sc.entered_required_count or sc.subject_total is null
        )
      ) = 0 as totals_complete,
      count(*) filter (where sc.counts_toward_average) as average_subject_count,
      count(*) filter (where sc.counts_toward_total) as total_subject_count,
      count(*) filter (
        where sc.counts_toward_average and (
          sc.result_id is null or sc.required_count = 0
          or sc.required_count <> sc.entered_required_count or sc.subject_total is null
        )
      ) = 0 as average_subjects_complete
    from public.class_enrollments e
    cross join target_class tc
    left join subject_calculations sc on sc.student_id = e.student_id
    where e.class_id = p_class_id and e.academic_session_id = p_academic_session_id
    group by e.student_id, e.division, tc.is_stream_class
  ),
  ranked as (
    select
      ss.*,
      ss.totals_complete and ss.total_subject_count > 0
        and ss.average_subjects_complete
        and (not ss.is_stream_class or ss.average_subject_count = 9) as complete,
      case
        when ss.totals_complete and ss.total_subject_count > 0
          and ss.average_subjects_complete
          and (not ss.is_stream_class or ss.average_subject_count = 9)
        then ss.calculated_total
      end as total_score,
      case
        when ss.totals_complete and ss.total_subject_count > 0
          and ss.average_subjects_complete
          and (not ss.is_stream_class or ss.average_subject_count = 9)
        then ss.calculated_average_total / case
          when ss.is_stream_class then 9
          else ss.average_subject_count
        end
      end as average_value
    from student_summaries ss
  ),
  positioned as (
    select
      r.*,
      case when r.complete then rank() over (
        partition by case when r.division in ('science', 'arts') then r.division end
        order by r.average_value desc nulls last
      ) end as rank_position
    from ranked r
  )
  select
    p.student_id,
    s.admission_number,
    trim(concat_ws(' ', s.first_name, s.other_names, s.last_name)),
    p.total_score,
    p.average_value,
    p.rank_position,
    p.complete,
    p.division
  from positioned p
  join public.students s on s.id = p.student_id
  order by p.division nulls first, p.average_value desc nulls last, s.last_name, s.first_name;
end;
$$;

revoke all on function public.get_class_standings(uuid, uuid, uuid) from public;
grant execute on function public.get_class_standings(uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
