do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'buddy_tasks'
  ) then
    alter publication supabase_realtime add table public.buddy_tasks;
  end if;
end
$$;
