do $$
declare
  v_session_id uuid;
  v_components jsonb;
  v_subject_names constant text[] := array[
    'Mathematics',
    'English Studies',
    'Verbal Reasoning',
    'Quantitative Reasoning',
    'Asusu Igbo',
    'Basic Science/Technology',
    'Physical and Health Education',
    'Computer Science',
    'Social Studies',
    'Civic Education',
    'Christian Religious Studies',
    'Cultural and Creative Art',
    'Home Economics',
    'Agricultural Science',
    'Literature'
  ];
  v_subject_name text;
  v_subject_id uuid;
  v_class_record record;
  v_offering_id uuid;
  v_scheme_id uuid;
  v_component jsonb;
begin
  select id
  into v_session_id
  from public.academic_sessions
  where name = '2026/2027' and is_active
  order by starts_on desc
  limit 1;

  if v_session_id is null then
    raise exception 'Cannot add Primary subjects: active academic session 2026/2027 was not found';
  end if;

  select components
  into v_components
  from public.section_assessment_settings
  where stage = 'primary';

  if v_components is null then
    raise exception 'Cannot add Primary subjects: configure the Primary assessment scheme first';
  end if;

  foreach v_subject_name in array v_subject_names
  loop
    select s.id
    into v_subject_id
    from public.subjects s
    where lower(s.name) = lower(v_subject_name)
    limit 1;

    if v_subject_id is null then
      insert into public.subjects (name)
      values (v_subject_name)
      returning id into v_subject_id;
    else
      update public.subjects
      set is_active = true
      where id = v_subject_id;
    end if;

    for v_class_record in
      select c.id
      from public.classes c
      where c.is_active
        and c.stage = 'primary'
        and regexp_replace(upper(trim(c.name)), '[[:space:]]+', ' ', 'g')
          ~ '^BASIC[[:space:]]*[1-6]([^0-9].*)?$'
    loop
      insert into public.class_subject_offerings (
        class_id, subject_id, academic_session_id, is_active
      )
      values (v_class_record.id, v_subject_id, v_session_id, true)
      on conflict (class_id, subject_id, academic_session_id) do update
        set is_active = true
      returning id into v_offering_id;

      if not exists (
        select 1
        from public.assessment_schemes
        where class_subject_offering_id = v_offering_id
          and is_current
      ) then
        insert into public.assessment_schemes (
          class_subject_offering_id, name, is_current
        )
        values (v_offering_id, 'Primary section assessment', true)
        returning id into v_scheme_id;

        for v_component in
          select value from jsonb_array_elements(v_components)
        loop
          insert into public.assessment_components (
            assessment_scheme_id, code, name, max_score, display_order,
            counts_toward_total, is_required
          )
          values (
            v_scheme_id,
            v_component->>'code',
            v_component->>'name',
            (v_component->>'max_score')::numeric,
            (v_component->>'display_order')::smallint,
            (v_component->>'counts_toward_total')::boolean,
            coalesce((v_component->>'is_required')::boolean, true)
          );
        end loop;
      end if;
    end loop;
  end loop;
end;
$$;
