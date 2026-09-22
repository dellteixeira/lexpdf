-- Accountless AI quota for private LexPDF installations.
--
-- AI requests no longer require a Supabase user. Each app installation keeps a
-- random opaque credential in device secure storage; the Worker hashes that
-- credential and sends only the hash-derived principal key to this function.
-- A global daily cap protects the private Workers AI endpoint against abuse even
-- if someone fabricates many installation identifiers.

create table if not exists public.ai_principal_daily_usage (
  principal_key text not null
    check (char_length(principal_key) between 20 and 160),
  usage_date date not null,
  credits_used integer not null default 0 check (credits_used >= 0),
  requests integer not null default 0 check (requests >= 0),
  rate_window_started_at timestamptz not null default now(),
  rate_window_requests integer not null default 0 check (rate_window_requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (principal_key, usage_date)
);

create table if not exists public.ai_global_daily_usage (
  usage_date date primary key,
  credits_used integer not null default 0 check (credits_used >= 0),
  requests integer not null default 0 check (requests >= 0),
  updated_at timestamptz not null default now()
);

create index if not exists ai_principal_daily_usage_updated_idx
  on public.ai_principal_daily_usage(updated_at desc);

alter table public.ai_principal_daily_usage enable row level security;
alter table public.ai_global_daily_usage enable row level security;

revoke all on public.ai_principal_daily_usage from public, anon, authenticated;
revoke all on public.ai_global_daily_usage from public, anon, authenticated;
grant select, insert, update, delete on public.ai_principal_daily_usage to service_role;
grant select, insert, update, delete on public.ai_global_daily_usage to service_role;

create or replace function public.consume_ai_principal_quota(
  p_principal_key text,
  p_credit_cost integer,
  p_daily_limit integer,
  p_minute_limit integer default 12,
  p_global_daily_limit integer default 1200
)
returns table(
  allowed boolean,
  reason text,
  credits_used integer,
  credits_remaining integer,
  requests integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'utc')::date;
  v_used integer;
  v_requests integer;
  v_window_started timestamptz;
  v_window_requests integer;
  v_global_used integer;
  v_global_requests integer;
begin
  if p_principal_key is null
     or char_length(trim(p_principal_key)) < 20
     or char_length(p_principal_key) > 160 then
    raise exception 'AI principal key is invalid';
  end if;

  if p_credit_cost < 1
     or p_daily_limit < 1
     or p_minute_limit < 1
     or p_global_daily_limit < 1 then
    raise exception 'AI quota arguments must be positive';
  end if;

  -- Lock global first for a consistent lock order across all principals.
  insert into public.ai_global_daily_usage (usage_date)
  values (v_day)
  on conflict (usage_date) do nothing;

  select g.credits_used, g.requests
    into v_global_used, v_global_requests
  from public.ai_global_daily_usage g
  where g.usage_date = v_day
  for update;

  insert into public.ai_principal_daily_usage (principal_key, usage_date)
  values (p_principal_key, v_day)
  on conflict (principal_key, usage_date) do nothing;

  select u.credits_used,
         u.requests,
         u.rate_window_started_at,
         u.rate_window_requests
    into v_used, v_requests, v_window_started, v_window_requests
  from public.ai_principal_daily_usage u
  where u.principal_key = p_principal_key
    and u.usage_date = v_day
  for update;

  if v_window_started <= now() - interval '60 seconds' then
    v_window_started := now();
    v_window_requests := 0;
  end if;

  if v_window_requests >= p_minute_limit then
    return query select false, 'rate_limit'::text, v_used,
      greatest(p_daily_limit - v_used, 0), v_requests;
    return;
  end if;

  if v_used + p_credit_cost > p_daily_limit then
    return query select false, 'daily_limit'::text, v_used,
      greatest(p_daily_limit - v_used, 0), v_requests;
    return;
  end if;

  if v_global_used + p_credit_cost > p_global_daily_limit then
    return query select false, 'global_limit'::text, v_used,
      greatest(p_daily_limit - v_used, 0), v_requests;
    return;
  end if;

  v_used := v_used + p_credit_cost;
  v_requests := v_requests + 1;
  v_window_requests := v_window_requests + 1;
  v_global_used := v_global_used + p_credit_cost;
  v_global_requests := v_global_requests + 1;

  update public.ai_principal_daily_usage u
  set credits_used = v_used,
      requests = v_requests,
      rate_window_started_at = v_window_started,
      rate_window_requests = v_window_requests,
      updated_at = now()
  where u.principal_key = p_principal_key
    and u.usage_date = v_day;

  update public.ai_global_daily_usage g
  set credits_used = v_global_used,
      requests = v_global_requests,
      updated_at = now()
  where g.usage_date = v_day;

  return query select true, 'ok'::text, v_used,
    greatest(p_daily_limit - v_used, 0), v_requests;
end;
$$;

revoke all on function public.consume_ai_principal_quota(text, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_ai_principal_quota(text, integer, integer, integer, integer)
  to service_role;

comment on table public.ai_principal_daily_usage is
  'Server-only AI usage counters keyed by hashed LexPDF account or installation principal.';

comment on table public.ai_global_daily_usage is
  'Server-only global AI daily cap protecting the personal Workers AI endpoint.';
