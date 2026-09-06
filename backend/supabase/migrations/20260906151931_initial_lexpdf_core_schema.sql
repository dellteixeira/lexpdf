-- LexPDF core schema snapshot.
-- Applied to Supabase project ibffselezupggrovfruz on 2026-09-06.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  filename text not null,
  mime_type text not null default 'application/pdf',
  provider text not null default 'local' check (provider in ('local','google_drive','onedrive','icloud','r2')),
  provider_file_id text,
  local_path text,
  remote_path text,
  file_size bigint check (file_size is null or file_size >= 0),
  page_count integer check (page_count is null or page_count >= 0),
  checksum text,
  remote_version text,
  local_version bigint not null default 1 check (local_version >= 1),
  is_available_offline boolean not null default true,
  sync_status text not null default 'local_only' check (sync_status in ('local_only','remote_only','synced','sync_pending','downloading','uploading','conflict','error')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_opened_at timestamptz
);

create table if not exists public.notebooks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  cover_data jsonb not null default '{}'::jsonb,
  paper_template text not null default 'blank',
  page_size text not null default 'a4',
  is_infinite_canvas boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  notebook_id uuid references public.notebooks(id) on delete cascade,
  document_id uuid references public.documents(id) on delete cascade,
  page_number integer not null check (page_number >= 1),
  width numeric,
  height numeric,
  background_type text not null default 'blank',
  background_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (notebook_id is not null or document_id is not null)
);

create table if not exists public.annotations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid references public.documents(id) on delete cascade,
  page_id uuid references public.pages(id) on delete cascade,
  page_number integer check (page_number is null or page_number >= 1),
  type text not null check (type in ('highlight','underline','strikeout','ink','text','note','shape','stamp','signature','image')),
  selected_text text,
  geometry jsonb not null default '{}'::jsonb,
  color text,
  opacity numeric not null default 1 check (opacity >= 0 and opacity <= 1),
  thickness numeric,
  content text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.strokes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  page_id uuid not null references public.pages(id) on delete cascade,
  tool text not null check (tool in ('pen','pencil','fountain_pen','ballpoint','marker','highlighter','eraser')),
  points jsonb not null,
  pressure jsonb,
  tilt jsonb,
  color text not null default '#000000',
  opacity numeric not null default 1 check (opacity >= 0 and opacity <= 1),
  width numeric not null default 1 check (width > 0),
  layer text not null default 'ink',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  page_number integer not null check (page_number >= 1),
  label text,
  created_at timestamptz not null default now()
);

create table if not exists public.reading_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  page_number integer not null default 1 check (page_number >= 1),
  zoom numeric not null default 1 check (zoom > 0),
  scroll_offset numeric not null default 0,
  view_mode text not null default 'continuous',
  updated_at timestamptz not null default now(),
  primary key (user_id, document_id)
);

create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  color text,
  created_at timestamptz not null default now()
);

create table if not exists public.document_tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (document_id, tag_id)
);

create table if not exists public.cloud_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('google_drive','onedrive','icloud','r2')),
  provider_account_id text,
  display_name text,
  encrypted_token_ref text,
  status text not null default 'connected' check (status in ('connected','expired','revoked','error')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid references public.documents(id) on delete cascade,
  notebook_id uuid references public.notebooks(id) on delete cascade,
  provider text not null,
  operation text not null check (operation in ('upload','download','delete','rename','move','metadata_update')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','processing','completed','failed')),
  attempts integer not null default 0 check (attempts >= 0),
  next_retry_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid references public.documents(id) on delete cascade,
  notebook_id uuid references public.notebooks(id) on delete cascade,
  local_version text,
  remote_version text,
  local_checksum text,
  remote_checksum text,
  resolution text check (resolution in ('keep_local','keep_remote','keep_both','merged')),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.backup_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'local',
  backup_type text not null default 'full' check (backup_type in ('full','incremental')),
  location text,
  checksum text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  status text not null default 'pending' check (status in ('pending','validating','valid','failed')),
  created_at timestamptz not null default now(),
  validated_at timestamptz
);

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_name text,
  platform text not null check (platform in ('android','windows','macos','ios','linux')),
  app_version text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists documents_user_updated_idx on public.documents(user_id, updated_at desc);
create index if not exists documents_user_provider_idx on public.documents(user_id, provider);
create index if not exists notebooks_user_updated_idx on public.notebooks(user_id, updated_at desc);
create index if not exists pages_notebook_page_idx on public.pages(notebook_id, page_number);
create index if not exists pages_document_page_idx on public.pages(document_id, page_number);
create index if not exists annotations_document_page_idx on public.annotations(document_id, page_number);
create index if not exists annotations_page_idx on public.annotations(page_id);
create index if not exists annotations_user_type_idx on public.annotations(user_id, type);
create index if not exists strokes_page_idx on public.strokes(page_id);
create index if not exists sync_queue_pending_idx on public.sync_queue(user_id, status, next_retry_at);
create index if not exists sync_conflicts_user_idx on public.sync_conflicts(user_id, created_at desc);
create index if not exists backup_history_user_idx on public.backup_history(user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.documents enable row level security;
alter table public.notebooks enable row level security;
alter table public.pages enable row level security;
alter table public.annotations enable row level security;
alter table public.strokes enable row level security;
alter table public.bookmarks enable row level security;
alter table public.reading_progress enable row level security;
alter table public.tags enable row level security;
alter table public.document_tags enable row level security;
alter table public.cloud_accounts enable row level security;
alter table public.sync_queue enable row level security;
alter table public.sync_conflicts enable row level security;
alter table public.backup_history enable row level security;
alter table public.devices enable row level security;

create policy profiles_owner_all on public.profiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['documents','notebooks','pages','annotations','strokes','bookmarks','reading_progress','tags','document_tags','cloud_accounts','sync_queue','sync_conflicts','backup_history','devices']
  loop
    execute format('create policy %I_owner_all on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t, t);
  end loop;
end $$;

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger documents_updated_at before update on public.documents for each row execute function public.set_updated_at();
create trigger notebooks_updated_at before update on public.notebooks for each row execute function public.set_updated_at();
create trigger pages_updated_at before update on public.pages for each row execute function public.set_updated_at();
create trigger annotations_updated_at before update on public.annotations for each row execute function public.set_updated_at();
create trigger strokes_updated_at before update on public.strokes for each row execute function public.set_updated_at();
create trigger cloud_accounts_updated_at before update on public.cloud_accounts for each row execute function public.set_updated_at();
create trigger sync_queue_updated_at before update on public.sync_queue for each row execute function public.set_updated_at();
