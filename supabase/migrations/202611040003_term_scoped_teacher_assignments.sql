alter table public.class_teacher_assignments
  add column if not exists term_id uuid;

alter table public.subject_teacher_assignments
  add column if not exists term_id uuid;

update public.class_teacher_assignments a
set term_id = t.id
from public.terms t
where a.term_id is null
  and t.academic_session_id = a.academic_session_id
  and t.is_active;

update public.class_teacher_assignments a
set term_id = t.id
from public.terms t
where a.term_id is null
  and t.academic_session_id = a.academic_session_id
  and t.term_number = 1;

update public.subject_teacher_assignments a
set term_id = t.id
from public.class_subject_offerings o
join public.terms t on t.academic_session_id = o.academic_session_id
where a.term_id is null
  and o.id = a.class_subject_offering_id
  and t.is_active;

update public.subject_teacher_assignments a
set term_id = t.id
from public.class_subject_offerings o
join public.terms t on t.academic_session_id = o.academic_session_id
where a.term_id is null
  and o.id = a.class_subject_offering_id
  and t.term_number = 1;

alter table public.class_teacher_assignments
  alter column term_id set not null;

alter table public.subject_teacher_assignments
  alter column term_id set not null;

alter table public.class_teacher_assignments
  add constraint class_teacher_assignments_term_fk
  foreign key (term_id, academic_session_id)
  references public.terms (id, academic_session_id)
  on delete restrict;

alter table public.subject_teacher_assignments
  add constraint subject_teacher_assignments_term_fk
  foreign key (term_id)
  references public.terms (id)
  on delete restrict;

alter table public.class_teacher_assignments
  drop constraint if exists class_teacher_assignments_teacher_id_class_id_academic_session_id_key;

alter table public.class_teacher_assignments
  add constraint class_teacher_assignments_teacher_class_session_term_key
  unique (teacher_id, class_id, academic_session_id, term_id);

alter table public.subject_teacher_assignments
  drop constraint if exists subject_teacher_assignments_teacher_id_class_subject_offering_id_key;

alter table public.subject_teacher_assignments
  add constraint subject_teacher_assignments_teacher_offering_term_key
  unique (teacher_id, class_subject_offering_id, term_id);

create index if not exists class_teacher_assignments_teacher_term_idx
  on public.class_teacher_assignments (teacher_id, term_id);

create index if not exists subject_teacher_assignments_teacher_term_idx
  on public.subject_teacher_assignments (teacher_id, term_id);

create or replace function public.validate_teacher_assignment_term()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  offering_session uuid;
begin
  if tg_table_name = 'class_teacher_assignments' then
    if not exists (
      select 1 from public.terms
      where id = new.term_id
        and academic_session_id = new.academic_session_id
    ) then
      raise exception 'The class teacher assignment term must belong to its academic session';
    end if;
  else
    select academic_session_id into offering_session
    from public.class_subject_offerings
    where id = new.class_subject_offering_id;
    if not exists (
      select 1 from public.terms
      where id = new.term_id
        and academic_session_id = offering_session
    ) then
      raise exception 'The subject teacher assignment term must belong to its offering session';
    end if;
  end if;
  return new;
end;
$$;

create trigger class_teacher_assignment_term_check
before insert or update on public.class_teacher_assignments
for each row execute function public.validate_teacher_assignment_term();

create trigger subject_teacher_assignment_term_check
before insert or update on public.subject_teacher_assignments
for each row execute function public.validate_teacher_assignment_term();

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
    join public.profiles p on p.id = auth.uid() and p.is_active
    where r.id = p_result_id
      and r.status = 'draft'
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

create or replace function public.can_read_result(p_result_id uuid)
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
    join public.profiles p on p.id = auth.uid() and p.is_active
    where r.id = p_result_id
      and not public.is_scoped_permission_denied('results.read', r.class_id, o.subject_id, r.academic_session_id)
      and (
        p.role = 'administrator'
        or public.has_scoped_permission('results.read', r.class_id, o.subject_id, r.academic_session_id)
        or exists (
          select 1
          from public.class_teacher_assignments a
          where a.teacher_id = auth.uid()
            and a.class_id = r.class_id
            and a.academic_session_id = r.academic_session_id
            and a.term_id = r.term_id
        )
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
  select public.is_active_administrator()
    or exists (
      select 1
      from public.class_subject_offerings o
      join public.profiles p on p.id = auth.uid() and p.is_active
      join public.terms t on t.academic_session_id = p_academic_session_id
        and t.is_active
      where o.id = p_class_subject_offering_id
        and o.class_id = p_class_id
        and o.academic_session_id = p_academic_session_id
        and not public.is_scoped_permission_denied('results.edit', p_class_id, o.subject_id, p_academic_session_id)
        and exists (
          select 1
          from public.class_enrollments e
          where e.student_id = p_student_id
            and e.class_id = p_class_id
            and e.academic_session_id = p_academic_session_id
        )
        and (
          public.has_scoped_permission('results.edit', p_class_id, o.subject_id, p_academic_session_id)
          or exists (
            select 1
            from public.subject_teacher_assignments a
            where a.teacher_id = auth.uid()
              and a.class_subject_offering_id = o.id
              and a.term_id = t.id
          )
        )
    );
$$;
