-- Coin League production hardening for Supabase
-- Run in Supabase SQL Editor after checking existing column names.

create extension if not exists pgcrypto;

create table if not exists public.league_admins (
  league_id text not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin')),
  created_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

-- After Google login, add the first owner manually:
-- insert into public.league_admins(league_id, user_id, role)
-- values ('YOUR_LEAGUE_ID', 'YOUR_AUTH_USER_ID', 'owner');

alter table public.participants add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.participants add column if not exists reward_claimed boolean not null default false;
alter table public.participants add column if not exists reward_claimed_at timestamptz;

create unique index if not exists participants_league_user_uidx
  on public.participants(league_id, user_id)
  where user_id is not null;

create unique index if not exists holdings_participant_symbol_uidx
  on public.holdings(participant_id, symbol);

create or replace function public.is_league_admin(p_league_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.league_admins a
    where a.league_id = p_league_id
      and a.user_id = auth.uid()
  );
$$;

alter table public.leagues enable row level security;
alter table public.participants enable row level security;
alter table public.holdings enable row level security;
alter table public.trade_history enable row level security;
alter table public.positions enable row level security;
alter table public.league_admins enable row level security;

drop policy if exists "leagues read all" on public.leagues;
create policy "leagues read all" on public.leagues
for select using (true);

drop policy if exists "leagues admin write" on public.leagues;
create policy "leagues admin write" on public.leagues
for all using (public.is_league_admin(id))
with check (public.is_league_admin(id));

drop policy if exists "league admins read own" on public.league_admins;
create policy "league admins read own" on public.league_admins
for select using (user_id = auth.uid() or public.is_league_admin(league_id));

drop policy if exists "league admins owner write" on public.league_admins;
create policy "league admins owner write" on public.league_admins
for all using (
  exists (
    select 1 from public.league_admins a
    where a.league_id = league_admins.league_id
      and a.user_id = auth.uid()
      and a.role = 'owner'
  )
) with check (
  exists (
    select 1 from public.league_admins a
    where a.league_id = league_admins.league_id
      and a.user_id = auth.uid()
      and a.role = 'owner'
  )
);

drop policy if exists "participants read rankings" on public.participants;
create policy "participants read rankings" on public.participants
for select using (true);

drop policy if exists "participants insert own" on public.participants;
create policy "participants insert own" on public.participants
for insert with check (user_id = auth.uid());

drop policy if exists "participants owner or admin update" on public.participants;
create policy "participants owner or admin update" on public.participants
for update using (user_id = auth.uid() or public.is_league_admin(league_id))
with check (user_id = auth.uid() or public.is_league_admin(league_id));

drop policy if exists "holdings read all" on public.holdings;
create policy "holdings read all" on public.holdings
for select using (true);

drop policy if exists "holdings no direct client writes" on public.holdings;
create policy "holdings no direct client writes" on public.holdings
for all using (false) with check (false);

drop policy if exists "trade history read all" on public.trade_history;
create policy "trade history read all" on public.trade_history
for select using (true);

drop policy if exists "trade history no direct client writes" on public.trade_history;
create policy "trade history no direct client writes" on public.trade_history
for all using (false) with check (false);

drop policy if exists "positions read all" on public.positions;
create policy "positions read all" on public.positions
for select using (true);

drop policy if exists "positions no direct client writes" on public.positions;
create policy "positions no direct client writes" on public.positions
for all using (false) with check (false);

create or replace function public.claim_league_reward(
  p_league_id text,
  p_nickname text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_league public.leagues%rowtype;
  v_participant_id text;
begin
  if auth.uid() is null then
    raise exception 'login required';
  end if;

  select * into v_league
  from public.leagues
  where id = p_league_id and status = 'ACTIVE';

  if not found then
    raise exception 'active league not found';
  end if;

  insert into public.participants(id, league_id, nickname, cash, user_id, reward_claimed, reward_claimed_at)
  values (
    lower(replace(gen_random_uuid()::text, '-', '')),
    p_league_id,
    nullif(trim(p_nickname), ''),
    coalesce(v_league.initial_cash, 10000),
    auth.uid(),
    true,
    now()
  )
  on conflict (league_id, user_id) where user_id is not null
  do update set
    nickname = coalesce(nullif(trim(excluded.nickname), ''), participants.nickname),
    reward_claimed = true,
    reward_claimed_at = coalesce(participants.reward_claimed_at, now())
  returning id into v_participant_id;

  return v_participant_id;
end;
$$;

create or replace function public.buy_spot(
  p_participant_id text,
  p_symbol text,
  p_base text,
  p_name text,
  p_price numeric,
  p_amount numeric
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_participant public.participants%rowtype;
  v_qty numeric;
begin
  if p_price <= 0 or p_amount < 1 then
    raise exception 'invalid order';
  end if;

  select * into v_participant
  from public.participants
  where id = p_participant_id
  for update;

  if not found or v_participant.user_id <> auth.uid() then
    raise exception 'not your participant';
  end if;
  if v_participant.cash < p_amount then
    raise exception 'insufficient cash';
  end if;

  v_qty := p_amount / p_price;

  update public.participants
  set cash = cash - p_amount
  where id = p_participant_id;

  insert into public.holdings(id, participant_id, league_id, symbol, base, name, qty, avg_price)
  values (lower(replace(gen_random_uuid()::text, '-', '')), p_participant_id, v_participant.league_id, p_symbol, p_base, p_name, v_qty, p_price)
  on conflict (participant_id, symbol)
  do update set
    qty = holdings.qty + excluded.qty,
    avg_price = ((holdings.qty * holdings.avg_price) + (excluded.qty * excluded.avg_price)) / (holdings.qty + excluded.qty);

  insert into public.trade_history(id, participant_id, league_id, type, symbol, base, name, qty, price, amount, date_str)
  values (lower(replace(gen_random_uuid()::text, '-', '')), p_participant_id, v_participant.league_id, 'BUY', p_symbol, p_base, p_name, v_qty, p_price, p_amount, to_char(now(), 'MM-DD HH24:MI'));
end;
$$;
