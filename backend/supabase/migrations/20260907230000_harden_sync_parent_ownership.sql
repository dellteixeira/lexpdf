-- Audit hardening item 11: sync rows must be owned by the same user as
-- exactly one parent entity (document or notebook).

alter table public.sync_queue
  drop constraint if exists sync_queue_single_parent_check;
alter table public.sync_queue
  add constraint sync_queue_single_parent_check
  check (num_nonnulls(document_id, notebook_id) = 1);

alter table public.sync_conflicts
  drop constraint if exists sync_conflicts_single_parent_check;
alter table public.sync_conflicts
  add constraint sync_conflicts_single_parent_check
  check (num_nonnulls(document_id, notebook_id) = 1);

drop policy if exists sync_queue_parent_owner_guard on public.sync_queue;
create policy sync_queue_parent_owner_guard
on public.sync_queue
as restrictive
for all
to authenticated
using (
  user_id = (select auth.uid())
  and (
    (document_id is not null and notebook_id is null and exists (
      select 1
      from public.documents d
      where d.id = document_id
        and d.user_id = (select auth.uid())
    ))
    or
    (notebook_id is not null and document_id is null and exists (
      select 1
      from public.notebooks n
      where n.id = notebook_id
        and n.user_id = (select auth.uid())
    ))
  )
)
with check (
  user_id = (select auth.uid())
  and (
    (document_id is not null and notebook_id is null and exists (
      select 1
      from public.documents d
      where d.id = document_id
        and d.user_id = (select auth.uid())
    ))
    or
    (notebook_id is not null and document_id is null and exists (
      select 1
      from public.notebooks n
      where n.id = notebook_id
        and n.user_id = (select auth.uid())
    ))
  )
);

drop policy if exists sync_conflicts_parent_owner_guard on public.sync_conflicts;
create policy sync_conflicts_parent_owner_guard
on public.sync_conflicts
as restrictive
for all
to authenticated
using (
  user_id = (select auth.uid())
  and (
    (document_id is not null and notebook_id is null and exists (
      select 1
      from public.documents d
      where d.id = document_id
        and d.user_id = (select auth.uid())
    ))
    or
    (notebook_id is not null and document_id is null and exists (
      select 1
      from public.notebooks n
      where n.id = notebook_id
        and n.user_id = (select auth.uid())
    ))
  )
)
with check (
  user_id = (select auth.uid())
  and (
    (document_id is not null and notebook_id is null and exists (
      select 1
      from public.documents d
      where d.id = document_id
        and d.user_id = (select auth.uid())
    ))
    or
    (notebook_id is not null and document_id is null and exists (
      select 1
      from public.notebooks n
      where n.id = notebook_id
        and n.user_id = (select auth.uid())
    ))
  )
);

comment on policy sync_queue_parent_owner_guard on public.sync_queue is
  'Restrictive guard: sync jobs can only target exactly one document/notebook owned by auth.uid().';
comment on policy sync_conflicts_parent_owner_guard on public.sync_conflicts is
  'Restrictive guard: conflicts can only target exactly one document/notebook owned by auth.uid().';
