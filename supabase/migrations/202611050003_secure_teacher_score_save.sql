alter function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb)
  security definer;

alter function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb)
  set search_path = pg_catalog, public;

revoke all on function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.save_result_scores(uuid, uuid, uuid, uuid, uuid, uuid, jsonb)
  to authenticated;
