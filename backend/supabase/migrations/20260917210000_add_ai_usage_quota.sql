-- Server-side quota for the optional Workers AI explanation endpoint.
-- App clients cannot read or mutate this table/function directly.

create table if not exists public.ai_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null,
  credits_used integer not null default 0 check (credits_used >= 0),
  requests integer not null default 0 check (requests >= 0),
  rate_window_started_at timestamptz not null default now(),
  rate_window_requests integer not null default 0 check (rate_window_requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

create index if not exists ai_daily_usage_updated_idx
  on public.ai_daily_usage(updated_at desc);

alter table public.ai_daily_usage enable row level security;
revoke all on public.ai_daily_usage from public, anon, authenticated;
grant select, insert, update, delete on public.ai_daily_usage to service_role;

create or replace function public.consume_ai_daily_quota(
  p_user_id uuid,
  p_credit_cost integer,
  p_daily_limit integer,
  p_minute_limit integer default 12
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
begin
  if p_credit_cost < 1 or p_daily_limit < 1 or p_minute_limit < 1 then
    raise exception 'AI quota arguments must be positive';
  end if;

  insert into public.ai_daily_usage (user_id, usage_date)
  values (p_user_id, v_day)
  on conflict (user_id, usage_date) do nothing;

  select u.credits_used, u.requests, u.rate_window_started_at, u.rate_window_requests
    into v_used, v_requests, v_window_started, v_window_requests
  from public.ai_daily_usage u
  where u.user_id = p_user_id and u.usage_date = v_day
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

  v_used := v_used + p_credit_cost;
  v_requests := v_requests + 1;
  v_window_requests := v_window_requests + 1;

  update public.ai_daily_usage u
  set credits_used = v_used,
      requests = v_requests,
      rate_window_started_at = v_window_started,
      rate_window_requests = v_window_requests,
      updated_at = now()
  where u.user_id = p_user_id and u.usage_date = v_day;

  return query select true, 'ok'::text, v_used,
    greatest(p_daily_limit - v_used, 0), v_requests;
end;
$$;

revoke all on function public.consume_ai_daily_quota(uuid, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_ai_daily_quota(uuid, integer, integer, integer)
  to service_role;

comment on table public.ai_daily_usage is
  'Server-only daily/fixed-window usage counters for LexPDF Workers AI.';
