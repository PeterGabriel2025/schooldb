alter table public.class_subject_offerings
  add column counts_toward_total boolean not null default true;

alter table public.assessment_components
  add column is_required boolean not null default true;

create table public.result_correction_authorizations (
  transaction_id bigint not null,
  result_id uuid not null references public.student_subject_results (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  primary key (transaction_id, result_id, actor_id)
);

alter table public.result_correction_authorizations enable row level security;
revoke all on public.result_correction_authorizations from anon, authenticated;

create or replace function public.guard_result_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  is_admin boolean := public.is_active_administrator();
  correction_reason text;
  missing_required integer;
  required_count integer;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft'
       or new.submitted_by is not null
       or new.submitted_at is not null
       or new.reviewed_by is not null
       or new.reviewed_at is not null
       or new.approved_by is not null
       or new.approved_at is not null
       or new.locked_by is not null
       or new.locked_at is not null then
      raise exception 'Results must start as drafts without workflow metadata';
    end if;
    new.updated_at := now();
    return new;
  end if;

  if new.student_id is distinct from old.student_id
     or new.class_id is distinct from old.class_id
     or new.academic_session_id is distinct from old.academic_session_id
     or new.class_subject_offering_id is distinct from old.class_subject_offering_id
     or new.assessment_scheme_id is distinct from old.assessment_scheme_id
     or new.term_id is distinct from old.term_id then
    raise exception 'Result identity fields cannot be changed';
  end if;

  if new.status is not distinct from old.status then
    if new.submitted_by is distinct from old.submitted_by
       or new.submitted_at is distinct from old.submitted_at
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at
       or new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
       or new.locked_by is distinct from old.locked_by
       or new.locked_at is distinct from old.locked_at then
      raise exception 'Result workflow metadata can only change during a valid status transition';
    end if;
  elsif old.status = 'draft' and new.status = 'submitted' then
    if not is_admin and not public.can_edit_result(old.id) then
      raise exception 'Not authorized to submit this result' using errcode = '42501';
    end if;

    select count(*) filter (where s.id is null), count(*)
      into missing_required, required_count
    from public.assessment_components c
    left join public.result_component_scores s
      on s.result_id = old.id
     and s.assessment_component_id = c.id
    where c.assessment_scheme_id = old.assessment_scheme_id
      and c.is_required;

    if required_count = 0 or missing_required > 0 then
      raise exception 'Cannot submit until every required assessment component has a score';
    end if;

    new.submitted_by := auth.uid();
    new.submitted_at := now();
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.approved_by := null;
    new.approved_at := null;
    new.locked_by := null;
    new.locked_at := null;
  elsif old.status = 'submitted' and new.status = 'under_review' then
    if not is_admin then
      raise exception 'Only an administrator may review results' using errcode = '42501';
    end if;
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  elsif old.status in ('submitted', 'under_review') and new.status = 'approved' then
    if not is_admin then
      raise exception 'Only an administrator may approve results' using errcode = '42501';
    end if;
    new.approved_by := auth.uid();
    new.approved_at := now();
  elsif old.status = 'approved' and new.status = 'locked' then
    if not is_admin then
      raise exception 'Only an administrator may lock results' using errcode = '42501';
    end if;
    new.locked_by := auth.uid();
    new.locked_at := now();
  elsif old.status = 'locked' and new.status = 'draft' then
    if not is_admin then
      raise exception 'Only an administrator may reopen locked results' using errcode = '42501';
    end if;
    select a.reason into correction_reason
    from public.result_correction_authorizations a
    where a.transaction_id = txid_current()
      and a.result_id = old.id
      and a.actor_id = auth.uid()
    for update;

    if correction_reason is null then
      raise exception 'Use the audited correction workflow to reopen a locked result';
    end if;

    delete from public.result_correction_authorizations a
    where a.transaction_id = txid_current()
      and a.result_id = old.id
      and a.actor_id = auth.uid();

    new.submitted_by := null;
    new.submitted_at := null;
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.approved_by := null;
    new.approved_at := null;
    new.locked_by := null;
    new.locked_at := null;

    insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
    values (
      auth.uid(),
      'reopen_for_correction',
      'student_subject_result',
      old.id::text,
      jsonb_build_object('reason', correction_reason)
    );
  else
    raise exception 'Invalid result status transition: % to %', old.status, new.status;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop policy if exists results_admin_delete on public.student_subject_results;
revoke delete on public.student_subject_results from authenticated;

create or replace function public.validate_class_teacher_assignment_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  assigned_role public.app_role;
begin
  select p.role into assigned_role
  from public.profiles p
  where p.id = new.teacher_id
    and p.is_active;

  if assigned_role is null or assigned_role not in (
    'secondary_class_teacher', 'primary_teacher', 'nursery_teacher'
  ) then
    raise exception 'The assigned user is not an active class teacher';
  end if;

  return new;
end;
$$;

create trigger class_teacher_assignment_role_check
before insert or update on public.class_teacher_assignments
for each row execute function public.validate_class_teacher_assignment_role();

create or replace function public.validate_subject_teacher_assignment_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  assigned_role public.app_role;
begin
  select p.role into assigned_role
  from public.profiles p
  where p.id = new.teacher_id
    and p.is_active;

  if assigned_role is distinct from 'secondary_subject_teacher' then
    raise exception 'The assigned user is not an active secondary subject teacher';
  end if;

  return new;
end;
$$;

create trigger subject_teacher_assignment_role_check
before insert or update on public.subject_teacher_assignments
for each row execute function public.validate_subject_teacher_assignment_role();

create or replace function public.can_view_class_results(
  p_class_id uuid,
  p_academic_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_active_administrator()
    or (
      not exists (
        select 1
        from public.user_permission_overrides o
        join public.profiles p on p.id = o.user_id and p.is_active
        where o.user_id = auth.uid()
          and o.permission_key = 'results.read'
          and not o.allowed
          and (o.class_id is null or o.class_id = p_class_id)
          and (o.academic_session_id is null or o.academic_session_id = p_academic_session_id)
      )
      and (
        public.has_scoped_permission('results.read', p_class_id, null, p_academic_session_id)
        or exists (
          select 1
          from public.class_teacher_assignments a
          join public.profiles p on p.id = a.teacher_id and p.is_active
          where a.teacher_id = auth.uid()
            and a.class_id = p_class_id
            and a.academic_session_id = p_academic_session_id
        )
      )
    );
$$;

create or replace function public.can_manage_class_register(
  p_class_id uuid,
  p_academic_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_active_administrator()
    or (
      not public.is_scoped_permission_denied(
        'register.manage', p_class_id, null, p_academic_session_id
      )
      and (
        public.has_scoped_permission(
          'register.manage', p_class_id, null, p_academic_session_id
        )
        or exists (
          select 1
          from public.class_teacher_assignments a
          join public.profiles p on p.id = a.teacher_id and p.is_active
          where a.teacher_id = auth.uid()
            and a.class_id = p_class_id
            and a.academic_session_id = p_academic_session_id
        )
      )
    );
$$;

create unique index students_admission_number_case_insensitive
  on public.students (lower(admission_number));

create or replace function public.register_student(
  p_admission_number text,
  p_first_name text,
  p_last_name text,
  p_class_id uuid,
  p_academic_session_id uuid,
  p_other_names text default null,
  p_gender text default null,
  p_date_of_birth date default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_student_id uuid;
begin
  if not public.can_manage_class_register(p_class_id, p_academic_session_id) then
    raise exception 'Not authorized to register students in this class' using errcode = '42501';
  end if;

  if p_admission_number is null or length(trim(p_admission_number)) = 0
     or p_first_name is null or length(trim(p_first_name)) = 0
     or p_last_name is null or length(trim(p_last_name)) = 0 then
    raise exception 'Admission number, first name and last name are required';
  end if;

  if not exists (
    select 1
    from public.classes c
    join public.academic_sessions s on s.id = p_academic_session_id
    where c.id = p_class_id
      and c.is_active
  ) then
    raise exception 'Select an active class and academic session';
  end if;

  insert into public.students (
    admission_number, first_name, last_name, other_names, gender, date_of_birth
  )
  values (
    trim(p_admission_number),
    trim(p_first_name),
    trim(p_last_name),
    nullif(trim(p_other_names), ''),
    p_gender,
    p_date_of_birth
  )
  returning id into new_student_id;

  insert into public.class_enrollments (
    student_id, class_id, academic_session_id
  )
  values (new_student_id, p_class_id, p_academic_session_id);

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'register',
    'student',
    new_student_id::text,
    jsonb_build_object(
      'admission_number', trim(p_admission_number),
      'class_id', p_class_id,
      'academic_session_id', p_academic_session_id
    )
  );

  return new_student_id;
end;
$$;

create or replace function public.get_result_calculation(p_result_id uuid)
returns table (
  result_id uuid,
  student_id uuid,
  class_id uuid,
  subject_id uuid,
  academic_session_id uuid,
  term_id uuid,
  status public.result_status,
  component_scores jsonb,
  class_work numeric,
  exam_score numeric,
  subject_total numeric,
  maximum_total numeric,
  grade text,
  is_complete boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.can_read_result(p_result_id) then
    raise exception 'Not authorized to read this result' using errcode = '42501';
  end if;

  return query
  with target_result as (
    select r.id, r.student_id, r.class_id, r.academic_session_id, r.term_id,
           r.status, r.assessment_scheme_id, o.subject_id
    from public.student_subject_results r
    join public.class_subject_offerings o on o.id = r.class_subject_offering_id
    where r.id = p_result_id
  ),
  component_values as (
    select
      tr.id,
      count(c.id) filter (where c.is_required) as required_count,
      count(c.id) filter (where c.is_required and s.id is not null) as entered_required_count,
      sum(s.score) filter (
        where c.counts_toward_total and s.id is not null
      ) as total_score,
      sum(c.max_score) filter (where c.counts_toward_total) as maximum_score,
      sum(s.score) filter (
        where upper(c.code) in ('CA', 'TEST') and s.id is not null
      ) as class_work_score,
      sum(s.score) filter (
        where upper(c.code) = 'EXAM' and s.id is not null
      ) as examination_score,
      coalesce(
        jsonb_object_agg(c.code, s.score order by c.display_order)
          filter (where c.id is not null),
        '{}'::jsonb
      ) as scores
    from target_result tr
    left join public.assessment_components c
      on c.assessment_scheme_id = tr.assessment_scheme_id
    left join public.result_component_scores s
      on s.result_id = tr.id
     and s.assessment_component_id = c.id
    group by tr.id
  )
  select
    tr.id,
    tr.student_id,
    tr.class_id,
    tr.subject_id,
    tr.academic_session_id,
    tr.term_id,
    tr.status,
    cv.scores,
    cv.class_work_score,
    cv.examination_score,
    case when cv.required_count > 0
           and cv.required_count = cv.entered_required_count
         then cv.total_score end,
    cv.maximum_score,
    (
      select b.grade
      from public.grading_scales gs
      join public.grading_bands b on b.grading_scale_id = gs.id
      where gs.is_active
        and cv.required_count > 0
        and cv.required_count = cv.entered_required_count
        and cv.total_score between b.minimum_score and b.maximum_score
      order by b.minimum_score desc
      limit 1
    ),
    cv.required_count > 0
      and cv.required_count = cv.entered_required_count
  from target_result tr
  join component_values cv on cv.id = tr.id;
end;
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
      and o.is_active
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

create or replace function public.submit_result(p_result_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  result_row public.student_subject_results%rowtype;
  missing_required integer;
  required_count integer;
begin
  select * into result_row
  from public.student_subject_results
  where id = p_result_id
  for update;

  if not found then
    raise exception 'Result not found';
  end if;

  if result_row.status <> 'draft' or not public.can_edit_result(p_result_id) then
    raise exception 'This result cannot be submitted by the current user' using errcode = '42501';
  end if;

  select count(*) filter (where s.id is null), count(*)
    into missing_required, required_count
  from public.assessment_components c
  left join public.result_component_scores s
    on s.result_id = result_row.id
   and s.assessment_component_id = c.id
  where c.assessment_scheme_id = result_row.assessment_scheme_id
    and c.is_required;

  if required_count = 0 then
    raise exception 'Cannot submit: configure at least one required assessment component';
  end if;
  if missing_required > 0 then
    raise exception 'Cannot submit: % required score component(s) are missing', missing_required;
  end if;

  update public.student_subject_results
  set status = 'submitted',
      submitted_by = auth.uid(),
      submitted_at = now(),
      updated_at = now()
  where id = p_result_id;
end;
$$;

create or replace function public.set_result_under_review(p_result_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator may review results' using errcode = '42501';
  end if;

  update public.student_subject_results
  set status = 'under_review',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      updated_at = now()
  where id = p_result_id
    and status = 'submitted';

  if not found then
    raise exception 'Only submitted results can be moved under review';
  end if;
end;
$$;

create or replace function public.approve_result(p_result_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_status public.result_status;
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator may approve results' using errcode = '42501';
  end if;

  select status into current_status
  from public.student_subject_results
  where id = p_result_id
  for update;

  if not found or current_status not in ('submitted', 'under_review') then
    raise exception 'Only submitted or reviewed results can be approved';
  end if;

  update public.student_subject_results
  set status = 'approved',
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now()
  where id = p_result_id;
end;
$$;

create or replace function public.lock_result(p_result_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator may lock results' using errcode = '42501';
  end if;

  update public.student_subject_results
  set status = 'locked',
      locked_by = auth.uid(),
      locked_at = now(),
      updated_at = now()
  where id = p_result_id
    and status = 'approved';

  if not found then
    raise exception 'Only approved results can be locked';
  end if;
end;
$$;

create or replace function public.reopen_locked_result(
  p_result_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator may reopen locked results' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 10 then
    raise exception 'Provide a correction reason of at least 10 characters';
  end if;

  insert into public.result_correction_authorizations (
    transaction_id, result_id, actor_id, reason
  )
  values (txid_current(), p_result_id, auth.uid(), trim(p_reason));

  update public.student_subject_results
  set status = 'draft',
      updated_at = now()
  where id = p_result_id
    and status = 'locked';

  if not found then
    raise exception 'Only locked results can be reopened';
  end if;

end;
$$;

revoke all on function public.can_view_class_results(uuid, uuid) from public;
revoke all on function public.can_manage_class_register(uuid, uuid) from public;
revoke all on function public.register_student(text, text, text, uuid, uuid, text, text, date) from public;
revoke all on function public.get_result_calculation(uuid) from public;
revoke all on function public.get_class_standings(uuid, uuid, uuid) from public;
revoke all on function public.submit_result(uuid) from public;
revoke all on function public.set_result_under_review(uuid) from public;
revoke all on function public.approve_result(uuid) from public;
revoke all on function public.lock_result(uuid) from public;
revoke all on function public.reopen_locked_result(uuid, text) from public;

grant execute on function public.can_view_class_results(uuid, uuid) to authenticated;
grant execute on function public.can_manage_class_register(uuid, uuid) to authenticated;
grant execute on function public.register_student(text, text, text, uuid, uuid, text, text, date) to authenticated;
grant execute on function public.get_result_calculation(uuid) to authenticated;
grant execute on function public.get_class_standings(uuid, uuid, uuid) to authenticated;
grant execute on function public.submit_result(uuid) to authenticated;
grant execute on function public.set_result_under_review(uuid) to authenticated;
grant execute on function public.approve_result(uuid) to authenticated;
grant execute on function public.lock_result(uuid) to authenticated;
grant execute on function public.reopen_locked_result(uuid, text) to authenticated;
