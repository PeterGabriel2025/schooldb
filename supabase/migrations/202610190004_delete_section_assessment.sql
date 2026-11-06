create or replace function public.admin_delete_section_assessment(
  p_stage public.school_stage
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_administrator() then
    raise exception 'Only an active administrator can delete a section assessment'
      using errcode = '42501';
  end if;
  if p_stage is null then
    raise exception 'Select a school section';
  end if;
  if not exists (
    select 1 from public.section_assessment_settings
    where stage = p_stage
  ) then
    raise exception 'No saved assessment scheme exists for this section';
  end if;
  if exists (
    select 1
    from public.student_subject_results r
    join public.class_subject_offerings o on o.id = r.class_subject_offering_id
    join public.classes c on c.id = o.class_id
    where c.stage = p_stage and r.status = 'draft'
  ) then
    raise exception 'Finish or remove draft results in this section before deleting its assessment scheme';
  end if;

  delete from public.section_assessment_settings
  where stage = p_stage;

  update public.assessment_schemes s
  set is_current = false
  from public.class_subject_offerings o
  join public.classes c on c.id = o.class_id
  where s.class_subject_offering_id = o.id
    and c.stage = p_stage
    and s.is_current;

  delete from public.assessment_components component
  using public.assessment_schemes s,
        public.class_subject_offerings o,
        public.classes c
  where component.assessment_scheme_id = s.id
    and s.class_subject_offering_id = o.id
    and o.class_id = c.id
    and c.stage = p_stage
    and not exists (
      select 1 from public.student_subject_results r
      where r.assessment_scheme_id = s.id
    );

  delete from public.assessment_schemes s
  using public.class_subject_offerings o,
        public.classes c
  where s.class_subject_offering_id = o.id
    and o.class_id = c.id
    and c.stage = p_stage
    and not exists (
      select 1 from public.student_subject_results r
      where r.assessment_scheme_id = s.id
    );

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, summary)
  values (
    auth.uid(),
    'admin_delete',
    'section_assessment',
    p_stage::text,
    jsonb_build_object('historical_schemes_preserved', true)
  );
end;
$$;

revoke all on function public.admin_delete_section_assessment(public.school_stage)
  from public;
grant execute on function public.admin_delete_section_assessment(public.school_stage)
  to authenticated;
