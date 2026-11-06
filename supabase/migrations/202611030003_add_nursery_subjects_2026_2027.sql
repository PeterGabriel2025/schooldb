do $$
declare
  session_id uuid;
  section_components jsonb;
  subject_names constant text[] := array[
    'Letter Work',
    'Number Work',
    'Asusu Igbo',
    'Bible Knowledge',
    'Writing Skill',
    'Social Habit',
    'Health Habit',
    'Nursery Science',
    'Nursery Computer',
    'Verbal Reasoning',
    'Quantitative Reasoning'
  ];
  subject_name text;
  v_subject_id uuid;
  class_record record;
  offering_id uuid;
  scheme_id uuid;
  component jsonb;
begin
  select id
  into session_id
  from public.academic_sessions
  where name = '2026/2027' and is_active
  order by starts_on desc
  limit 1;

  if session_id is null then
    raise exception 'Cannot add Nursery subjects: active academic session 2026/2027 was not found';
  end if;

  select components
  into section_components
  from public.section_assessment_settings
  where stage = 'nursery';

  if section_components is null then
    raise exception 'Cannot add Nursery subjects: configure the Nursery assessment scheme first';
  end if;

  if not exists (
    select 1
    from public.classes c
    where is_active
      and stage = 'nursery'
      and regexp_replace(upper(trim(name)), '[[:space:]]+', ' ', 'g')
        ~ '^NURSERY[[:space:]]*[1-3]([^0-9].*)?$'
  ) then
    raise exception 'Cannot add Nursery subjects: no active Nursery 1–3 classes were found';
  end if;

  if not exists (
    select 1
    from public.classes c
    where is_active
      and stage = 'nursery'
      and regexp_replace(upper(trim(name)), '[[:space:]]+', ' ', 'g')
        ~ '^PRE[-[:space:]]*NURSERY$'
  ) then
    raise exception 'Cannot add Nursery subjects: no active Pre-nursery class was found';
  end if;

  foreach subject_name in array subject_names
  loop
    select s.id
    into v_subject_id
    from public.subjects s
    where lower(s.name) = lower(subject_name)
    limit 1;

    if v_subject_id is null then
      insert into public.subjects (name)
      values (subject_name)
      returning id into v_subject_id;
    else
      update public.subjects s
      set is_active = true
      where s.id = v_subject_id;
    end if;

    for class_record in
      select c.id
      from public.classes c
      where is_active
        and stage = 'nursery'
        and (
          regexp_replace(upper(trim(name)), '[[:space:]]+', ' ', 'g')
            ~ '^NURSERY[[:space:]]*[1-3]([^0-9].*)?$'
          or regexp_replace(upper(trim(name)), '[[:space:]]+', ' ', 'g')
            ~ '^PRE[-[:space:]]*NURSERY$'
        )
    loop
      insert into public.class_subject_offerings (
        class_id, subject_id, academic_session_id, is_active
      )
      values (class_record.id, v_subject_id, session_id, true)
      on conflict (class_id, subject_id, academic_session_id) do update
        set is_active = true
      returning id into offering_id;

      if not exists (
        select 1
        from public.assessment_schemes
        where class_subject_offering_id = offering_id
          and is_current
      ) then
        insert into public.assessment_schemes (
          class_subject_offering_id, name, is_current
        )
        values (offering_id, 'Nursery section assessment', true)
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
            coalesce((component->>'is_required')::boolean, true)
          );
        end loop;
      end if;
    end loop;
  end loop;
end;
$$;
