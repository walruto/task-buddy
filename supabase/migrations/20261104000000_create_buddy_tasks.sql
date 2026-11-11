create table if not exists public.buddy_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 500),
  notes text,
  due_date date,
  completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.buddy_tasks enable row level security;

grant select, insert, update, delete on public.buddy_tasks to authenticated;

create policy "Users can read their own buddy tasks"
  on public.buddy_tasks for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own buddy tasks"
  on public.buddy_tasks for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own buddy tasks"
  on public.buddy_tasks for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can delete their own buddy tasks"
  on public.buddy_tasks for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.set_buddy_tasks_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists buddy_tasks_updated_at on public.buddy_tasks;
create trigger buddy_tasks_updated_at
before update on public.buddy_tasks
for each row execute function public.set_buddy_tasks_updated_at();
