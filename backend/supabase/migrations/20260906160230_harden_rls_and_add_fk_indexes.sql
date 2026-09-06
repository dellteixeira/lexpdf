-- Hardening pass after Supabase security/performance advisor review.

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

create index if not exists bookmarks_document_idx on public.bookmarks(document_id);
create index if not exists devices_user_idx on public.devices(user_id);
create index if not exists document_tags_tag_idx on public.document_tags(tag_id);
create index if not exists document_tags_user_idx on public.document_tags(user_id);
create index if not exists pages_user_idx on public.pages(user_id);
create index if not exists reading_progress_document_idx on public.reading_progress(document_id);
create index if not exists strokes_user_idx on public.strokes(user_id);
create index if not exists sync_conflicts_document_idx on public.sync_conflicts(document_id);
create index if not exists sync_conflicts_notebook_idx on public.sync_conflicts(notebook_id);
create index if not exists sync_queue_document_idx on public.sync_queue(document_id);
create index if not exists sync_queue_notebook_idx on public.sync_queue(notebook_id);

drop policy if exists profiles_owner_all on public.profiles;
create policy profiles_owner_all
on public.profiles
for all
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

do $$
declare t text;
begin
  foreach t in array array[
    'documents','notebooks','pages','annotations','strokes','bookmarks',
    'reading_progress','tags','document_tags','cloud_accounts','sync_queue',
    'sync_conflicts','backup_history','devices'
  ]
  loop
    execute format('drop policy if exists %I_owner_all on public.%I', t, t);
    execute format(
      'create policy %I_owner_all on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      t,
      t
    );
  end loop;
end $$;
