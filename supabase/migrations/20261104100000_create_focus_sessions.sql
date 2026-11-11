create table if not exists public.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null references public.buddy_tasks(id) on delete cascade,
  study_mode text not null check (study_mode in ('screen', 'paper')),
  sensitivity text not null check (sensitivity in ('relaxed', 'balanced', 'strict')),
  status text not null check (status in ('completed', 'ended')),
  planned_seconds integer not null check (planned_seconds in (1500, 2700, 3600)),
  elapsed_seconds integer not null check (elapsed_seconds between 0 and 86400),
  focused_seconds integer not null check (focused_seconds between 0 and elapsed_seconds),
  longest_streak_seconds integer not null check (longest_streak_seconds between 0 and elapsed_seconds),
  alert_count integer not null check (alert_count between 0 and 10000),
  started_at timestamptz not null,
  ended_at timestamptz not null check (ended_at >= started_at),
  created_at timestamptz not null default now()
);

create index if not exists focus_sessions_user_task_ended_idx
  on public.focus_sessions (user_id, task_id, ended_at desc);

alter table public.focus_sessions enable row level security;

grant select, insert on public.focus_sessions to authenticated;

create policy "Users can read their own focus sessions"
  on public.focus_sessions for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own focus sessions"
  on public.focus_sessions for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.buddy_tasks
      where buddy_tasks.id = focus_sessions.task_id
        and buddy_tasks.user_id = (select auth.uid())
    )
  );
