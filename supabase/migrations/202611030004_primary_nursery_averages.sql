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
      sum(
        sc.subject_total / case
          when exists (
            select 1 from public.classes c
            where c.id = p_class_id and c.stage in ('primary', 'nursery')
          ) then sc.required_count
          else 1
        end
      ) filter (
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
