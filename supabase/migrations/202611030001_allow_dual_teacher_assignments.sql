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
    and p.is_active
    and p.role <> 'administrator';

  if assigned_role is null then
    raise exception 'The assigned user is not an active teacher';
  end if;

  return new;
end;
$$;
