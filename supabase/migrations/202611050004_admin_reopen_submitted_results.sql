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
  elsif old.status in ('submitted', 'locked') and new.status = 'draft' then
    if not is_admin then
      raise exception 'Only an administrator may reopen results' using errcode = '42501';
    end if;

    select a.reason into correction_reason
    from public.result_correction_authorizations a
    where a.transaction_id = txid_current()
      and a.result_id = old.id
      and a.actor_id = auth.uid()
    for update;

    if correction_reason is null then
      raise exception 'Use the audited correction workflow to reopen a result';
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

create or replace function public.reopen_submitted_result(
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
    raise exception 'Only an active administrator may reopen submitted results'
      using errcode = '42501';
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
    and status = 'submitted';

  if not found then
    raise exception 'Only submitted results can be reopened';
  end if;
end;
$$;

revoke all on function public.reopen_submitted_result(uuid, text) from public, anon;
grant execute on function public.reopen_submitted_result(uuid, text) to authenticated;
