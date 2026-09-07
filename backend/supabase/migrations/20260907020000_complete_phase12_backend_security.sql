-- Phase 12 backend completion: Auth bootstrap, explicit grants, restrictive
-- ownership guards and server-only backend event persistence.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'display_name', ''),
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function private.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

create table if not exists public.backend_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null check (source in ('cloudflare_queue','cloudflare_worker','supabase')),
  event_type text not null,
  object_key text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists backend_events_user_created_idx
  on public.backend_events(user_id, created_at desc);

alter table public.backend_events enable row level security;
revoke all on public.backend_events from anon, authenticated;
grant select, insert, update, delete on public.backend_events to service_role;

-- Public Data API access is explicit. Signed-out requests receive no table access.
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','documents','notebooks','pages','annotations','strokes','bookmarks',
    'reading_progress','tags','document_tags','cloud_accounts','sync_queue',
    'sync_conflicts','backup_history','devices'
  ]
  loop
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- Child rows must belong to the same authenticated owner as their parents.
-- Restrictive policies compose with the existing owner policies.
drop policy if exists pages_parent_owner_guard on public.pages;
create policy pages_parent_owner_guard
on public.pages as restrictive for all to authenticated
using (
  user_id = (select auth.uid())
  and (notebook_id is null or exists (
    select 1 from public.notebooks n
    where n.id = notebook_id and n.user_id = (select auth.uid())
  ))
  and (document_id is null or exists (
    select 1 from public.documents d
    where d.id = document_id and d.user_id = (select auth.uid())
  ))
)
with check (
  user_id = (select auth.uid())
  and (notebook_id is null or exists (
    select 1 from public.notebooks n
    where n.id = notebook_id and n.user_id = (select auth.uid())
  ))
  and (document_id is null or exists (
    select 1 from public.documents d
    where d.id = document_id and d.user_id = (select auth.uid())
  ))
);

drop policy if exists annotations_parent_owner_guard on public.annotations;
create policy annotations_parent_owner_guard
on public.annotations as restrictive for all to authenticated
using (
  user_id = (select auth.uid())
  and (document_id is null or exists (
    select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid())
  ))
  and (page_id is null or exists (
    select 1 from public.pages p where p.id = page_id and p.user_id = (select auth.uid())
  ))
)
with check (
  user_id = (select auth.uid())
  and (document_id is null or exists (
    select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid())
  ))
  and (page_id is null or exists (
    select 1 from public.pages p where p.id = page_id and p.user_id = (select auth.uid())
  ))
);

drop policy if exists strokes_parent_owner_guard on public.strokes;
create policy strokes_parent_owner_guard
on public.strokes as restrictive for all to authenticated
using (
  user_id = (select auth.uid())
  and exists (select 1 from public.pages p where p.id = page_id and p.user_id = (select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.pages p where p.id = page_id and p.user_id = (select auth.uid()))
);

drop policy if exists document_tags_parent_owner_guard on public.document_tags;
create policy document_tags_parent_owner_guard
on public.document_tags as restrictive for all to authenticated
using (
  user_id = (select auth.uid())
  and exists (select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid()))
  and exists (select 1 from public.tags t where t.id = tag_id and t.user_id = (select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid()))
  and exists (select 1 from public.tags t where t.id = tag_id and t.user_id = (select auth.uid()))
);

drop policy if exists reading_progress_parent_owner_guard on public.reading_progress;
create policy reading_progress_parent_owner_guard
on public.reading_progress as restrictive for all to authenticated
using (
  user_id = (select auth.uid())
  and exists (select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid()))
);

drop policy if exists bookmarks_parent_owner_guard on public.bookmarks;
create policy bookmarks_parent_owner_guard
on public.bookmarks as restrictive for all to authenticated
using (
  user_id = (select auth.uid())
  and exists (select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid()))
)
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.documents d where d.id = document_id and d.user_id = (select auth.uid()))
);

-- Server-side queue/audit table intentionally has no anon/authenticated RLS policy.
comment on table public.backend_events is
  'Server-only audit sink for trusted backend infrastructure; not exposed to app clients.';
