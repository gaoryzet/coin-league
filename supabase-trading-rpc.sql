-- Coin League full shared trading backend
-- Run this once in Supabase SQL Editor.
-- It moves league participation, cash, spot holdings, futures positions, history, and ranking data to Supabase.

create extension if not exists pgcrypto;

create table if not exists public.leagues (
  id text primary key,
  name text not null default '코인왕 시즌 리그',
  ticket text,
  initial_cash numeric not null default 10000,
  start_date text,
  end_date text,
  status text not null default 'ACTIVE',
  winner_nickname text,
  created_at timestamptz not null default now()
);

alter table public.leagues add column if not exists ticket text;
alter table public.leagues add column if not exists initial_cash numeric not null default 10000;
alter table public.leagues add column if not exists start_date text;
alter table public.leagues add column if not exists end_date text;
alter table public.leagues add column if not exists status text not null default 'ACTIVE';
alter table public.leagues add column if not exists winner_nickname text;
alter table public.leagues add column if not exists created_at timestamptz not null default now();

create table if not exists public.participants (
  id text primary key,
  league_id text not null references public.leagues(id) on delete cascade,
  nickname text not null,
  cash numeric not null default 0,
  created_at timestamptz not null default now()
);

alter table public.participants add column if not exists league_id text references public.leagues(id) on delete cascade;
alter table public.participants add column if not exists nickname text;
alter table public.participants add column if not exists cash numeric not null default 0;
alter table public.participants add column if not exists created_at timestamptz not null default now();
alter table public.participants add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.participants add column if not exists reward_claimed boolean not null default false;
alter table public.participants add column if not exists reward_claimed_at timestamptz;

create unique index if not exists participants_league_user_uidx
  on public.participants(league_id, user_id)
  where user_id is not null;

-- Keep only one visible active league. Older active leagues are closed automatically.
with ranked_active as (
  select id, row_number() over (
    order by
      case when name = '리그 없음' then 1 else 0 end,
      created_at desc
  ) as rn
  from public.leagues
  where status = 'ACTIVE'
)
update public.leagues l
set status = 'CLOSED'
from ranked_active r
where l.id = r.id
  and r.rn > 1;

create unique index if not exists leagues_single_active_uidx
  on public.leagues((status))
  where status = 'ACTIVE';

create table if not exists public.holdings (
  id text primary key,
  participant_id text not null references public.participants(id) on delete cascade,
  league_id text not null references public.leagues(id) on delete cascade,
  symbol text not null,
  base text,
  name text,
  qty numeric not null default 0,
  avg_price numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.holdings add column if not exists participant_id text references public.participants(id) on delete cascade;
alter table public.holdings add column if not exists league_id text references public.leagues(id) on delete cascade;
alter table public.holdings add column if not exists symbol text;
alter table public.holdings add column if not exists base text;
alter table public.holdings add column if not exists name text;
alter table public.holdings add column if not exists qty numeric not null default 0;
alter table public.holdings add column if not exists avg_price numeric not null default 0;
alter table public.holdings add column if not exists created_at timestamptz not null default now();
alter table public.holdings add column if not exists updated_at timestamptz not null default now();

create unique index if not exists holdings_participant_symbol_uidx
  on public.holdings(participant_id, symbol);

create table if not exists public.positions (
  id text primary key,
  participant_id text not null references public.participants(id) on delete cascade,
  league_id text not null references public.leagues(id) on delete cascade,
  symbol text not null,
  name text,
  dir text not null check (dir in ('long','short')),
  lev numeric not null default 1,
  margin numeric not null default 0,
  size numeric not null default 0,
  entry_price numeric not null default 0,
  liq_price numeric not null default 0,
  status text not null default 'OPEN',
  exit_price numeric,
  pnl numeric,
  rate numeric,
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);

alter table public.positions add column if not exists participant_id text references public.participants(id) on delete cascade;
alter table public.positions add column if not exists league_id text references public.leagues(id) on delete cascade;
alter table public.positions add column if not exists symbol text;
alter table public.positions add column if not exists name text;
alter table public.positions add column if not exists dir text;
alter table public.positions add column if not exists lev numeric not null default 1;
alter table public.positions add column if not exists margin numeric not null default 0;
alter table public.positions add column if not exists size numeric not null default 0;
alter table public.positions add column if not exists entry_price numeric not null default 0;
alter table public.positions add column if not exists liq_price numeric not null default 0;
alter table public.positions add column if not exists status text not null default 'OPEN';
alter table public.positions add column if not exists exit_price numeric;
alter table public.positions add column if not exists pnl numeric;
alter table public.positions add column if not exists rate numeric;
alter table public.positions add column if not exists opened_at timestamptz not null default now();
alter table public.positions add column if not exists closed_at timestamptz;

create table if not exists public.trade_history (
  id text primary key,
  participant_id text not null references public.participants(id) on delete cascade,
  league_id text not null references public.leagues(id) on delete cascade,
  type text not null,
  symbol text,
  base text,
  name text,
  qty numeric,
  price numeric,
  amount numeric,
  pnl numeric,
  note text,
  date_str text,
  created_at timestamptz not null default now()
);

alter table public.trade_history add column if not exists participant_id text references public.participants(id) on delete cascade;
alter table public.trade_history add column if not exists league_id text references public.leagues(id) on delete cascade;
alter table public.trade_history add column if not exists type text;
alter table public.trade_history add column if not exists symbol text;
alter table public.trade_history add column if not exists base text;
alter table public.trade_history add column if not exists name text;
alter table public.trade_history add column if not exists qty numeric;
alter table public.trade_history add column if not exists price numeric;
alter table public.trade_history add column if not exists amount numeric;
alter table public.trade_history add column if not exists pnl numeric;
alter table public.trade_history add column if not exists note text;
alter table public.trade_history add column if not exists date_str text;
alter table public.trade_history add column if not exists created_at timestamptz not null default now();

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'super_admin',
  created_at timestamptz not null default now()
);

create table if not exists public.league_admins (
  league_id text not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin')),
  created_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

create or replace function public.is_app_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.app_admins a where a.user_id = auth.uid());
$$;

create or replace function public.is_league_admin(p_league_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_app_admin() or exists(
    select 1 from public.league_admins a
    where a.league_id = p_league_id and a.user_id = auth.uid()
  );
$$;

alter table public.leagues enable row level security;
alter table public.participants enable row level security;
alter table public.holdings enable row level security;
alter table public.positions enable row level security;
alter table public.trade_history enable row level security;
alter table public.app_admins enable row level security;
alter table public.league_admins enable row level security;

drop policy if exists "leagues read all" on public.leagues;
create policy "leagues read all" on public.leagues for select using (true);
drop policy if exists "leagues admin write" on public.leagues;
create policy "leagues admin write" on public.leagues for all using (public.is_league_admin(id)) with check (public.is_league_admin(id));

drop policy if exists "participants read rankings" on public.participants;
create policy "participants read rankings" on public.participants for select using (true);
drop policy if exists "participants insert own" on public.participants;
create policy "participants insert own" on public.participants for insert with check (user_id = auth.uid());
drop policy if exists "participants owner or admin update" on public.participants;
create policy "participants owner or admin update" on public.participants for update using (user_id = auth.uid() or public.is_league_admin(league_id)) with check (user_id = auth.uid() or public.is_league_admin(league_id));

drop policy if exists "holdings read all" on public.holdings;
create policy "holdings read all" on public.holdings for select using (true);
drop policy if exists "holdings no direct client writes" on public.holdings;
create policy "holdings no direct client writes" on public.holdings for all using (false) with check (false);

drop policy if exists "positions read all" on public.positions;
create policy "positions read all" on public.positions for select using (true);
drop policy if exists "positions no direct client writes" on public.positions;
create policy "positions no direct client writes" on public.positions for all using (false) with check (false);

drop policy if exists "trade history read all" on public.trade_history;
create policy "trade history read all" on public.trade_history for select using (true);
drop policy if exists "trade history no direct client writes" on public.trade_history;
create policy "trade history no direct client writes" on public.trade_history for all using (false) with check (false);

drop policy if exists "app admins read own" on public.app_admins;
create policy "app admins read own" on public.app_admins for select using (user_id = auth.uid());
drop policy if exists "league admins read own" on public.league_admins;
create policy "league admins read own" on public.league_admins for select using (user_id = auth.uid() or public.is_league_admin(league_id));

create or replace function public.new_text_id()
returns text language sql volatile as $$
  select lower(replace(gen_random_uuid()::text, '-', ''));
$$;

create or replace function public.claim_league_reward(p_league_id text, p_nickname text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_league public.leagues%rowtype;
  v_id text;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select * into v_league from public.leagues where id = p_league_id and status = 'ACTIVE';
  if not found then raise exception 'active league not found'; end if;

  insert into public.participants(id, league_id, nickname, cash, user_id, reward_claimed, reward_claimed_at)
  values (public.new_text_id(), p_league_id, nullif(trim(p_nickname), ''), coalesce(v_league.initial_cash, 10000), auth.uid(), true, now())
  on conflict (league_id, user_id) where user_id is not null
  do update set
    nickname = coalesce(nullif(trim(excluded.nickname), ''), participants.nickname),
    cash = case
      when participants.reward_claimed then participants.cash
      else coalesce(v_league.initial_cash, 10000)
    end,
    reward_claimed = true,
    reward_claimed_at = coalesce(participants.reward_claimed_at, now())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.assert_own_participant(p_participant_id text)
returns public.participants language plpgsql security definer set search_path = public as $$
declare
  v public.participants%rowtype;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select * into v from public.participants where id = p_participant_id for update;
  if not found or v.user_id <> auth.uid() then raise exception 'not your participant'; end if;
  if not v.reward_claimed then raise exception 'reward not claimed'; end if;
  return v;
end;
$$;

create or replace function public.place_spot_order(
  p_participant_id text,
  p_side text,
  p_symbol text,
  p_name text,
  p_price numeric,
  p_amount numeric
) returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_participant public.participants%rowtype;
  v_holding public.holdings%rowtype;
  v_qty numeric;
  v_pnl numeric := null;
begin
  if p_price <= 0 or p_amount < 1 then raise exception 'invalid order'; end if;
  v_participant := public.assert_own_participant(p_participant_id);
  v_qty := p_amount / p_price;

  if p_side = 'buy' then
    if v_participant.cash < p_amount then raise exception 'insufficient cash'; end if;
    update public.participants set cash = cash - p_amount where id = p_participant_id;
    insert into public.holdings(id, participant_id, league_id, symbol, name, qty, avg_price)
    values (public.new_text_id(), p_participant_id, v_participant.league_id, p_symbol, p_name, v_qty, p_price)
    on conflict (participant_id, symbol)
    do update set
      qty = holdings.qty + excluded.qty,
      avg_price = ((holdings.qty * holdings.avg_price) + (excluded.qty * excluded.avg_price)) / nullif(holdings.qty + excluded.qty, 0),
      updated_at = now();
    insert into public.trade_history(id, participant_id, league_id, type, symbol, name, qty, price, amount, date_str, note)
    values (public.new_text_id(), p_participant_id, v_participant.league_id, '매수', p_symbol, p_name, v_qty, p_price, p_amount, to_char(now(), 'MM-DD HH24:MI'), '현물');
    return 0;
  elsif p_side = 'sell' then
    select * into v_holding from public.holdings where participant_id = p_participant_id and symbol = p_symbol for update;
    if not found or v_holding.qty <= 0 then raise exception 'no holding'; end if;
    if p_amount > v_holding.qty * p_price + 0.000001 then raise exception 'amount exceeds holding value'; end if;
    v_pnl := p_amount - (v_qty * v_holding.avg_price);
    update public.holdings set qty = qty - v_qty, updated_at = now() where id = v_holding.id;
    delete from public.holdings where id = v_holding.id and qty <= 0.0000000001;
    update public.participants set cash = cash + p_amount where id = p_participant_id;
    insert into public.trade_history(id, participant_id, league_id, type, symbol, name, qty, price, amount, pnl, date_str, note)
    values (public.new_text_id(), p_participant_id, v_participant.league_id, '매도', p_symbol, p_name, v_qty, p_price, p_amount, v_pnl, to_char(now(), 'MM-DD HH24:MI'), '현물');
    return v_pnl;
  else
    raise exception 'invalid side';
  end if;
end;
$$;

create or replace function public.open_future_position(
  p_participant_id text,
  p_symbol text,
  p_name text,
  p_dir text,
  p_lev numeric,
  p_margin numeric,
  p_entry numeric,
  p_liq numeric
) returns text language plpgsql security definer set search_path = public as $$
declare
  v_participant public.participants%rowtype;
  v_id text;
begin
  if p_dir not in ('long','short') then raise exception 'invalid direction'; end if;
  if p_lev < 1 or p_margin < 1 or p_entry <= 0 then raise exception 'invalid position'; end if;
  v_participant := public.assert_own_participant(p_participant_id);
  if v_participant.cash < p_margin then raise exception 'insufficient cash'; end if;

  update public.participants set cash = cash - p_margin where id = p_participant_id;
  v_id := public.new_text_id();
  insert into public.positions(id, participant_id, league_id, symbol, name, dir, lev, margin, size, entry_price, liq_price, status)
  values (v_id, p_participant_id, v_participant.league_id, p_symbol, p_name, p_dir, p_lev, p_margin, p_margin * p_lev, p_entry, p_liq, 'OPEN');
  insert into public.trade_history(id, participant_id, league_id, type, symbol, name, price, amount, date_str, note)
  values (public.new_text_id(), p_participant_id, v_participant.league_id, '포지션 오픈', p_symbol, p_name, p_entry, p_margin, to_char(now(), 'MM-DD HH24:MI'), p_lev || 'x ' || upper(p_dir));
  return v_id;
end;
$$;

create or replace function public.close_future_position(p_position_id text, p_exit numeric)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_pos public.positions%rowtype;
  v_participant public.participants%rowtype;
  v_move numeric;
  v_pnl numeric;
  v_rate numeric;
  v_returned numeric;
  v_status text;
begin
  if p_exit <= 0 then raise exception 'invalid exit price'; end if;
  select * into v_pos from public.positions where id = p_position_id and status = 'OPEN' for update;
  if not found then raise exception 'open position not found'; end if;
  v_participant := public.assert_own_participant(v_pos.participant_id);

  if (v_pos.dir = 'long' and p_exit <= v_pos.liq_price) or (v_pos.dir = 'short' and p_exit >= v_pos.liq_price) then
    v_pnl := -v_pos.margin;
    v_rate := -100;
    v_returned := 0;
    v_status := 'LIQUIDATED';
  else
    v_move := case when v_pos.dir = 'long' then (p_exit - v_pos.entry_price) / v_pos.entry_price else (v_pos.entry_price - p_exit) / v_pos.entry_price end;
    v_pnl := v_move * v_pos.size;
    v_rate := v_move * v_pos.lev * 100;
    v_returned := greatest(0, v_pos.margin + v_pnl);
    v_status := 'CLOSED';
  end if;

  update public.positions
  set status = v_status, exit_price = p_exit, pnl = v_pnl, rate = v_rate, closed_at = now()
  where id = p_position_id;
  update public.participants set cash = cash + v_returned where id = v_pos.participant_id;
  insert into public.trade_history(id, participant_id, league_id, type, symbol, name, price, amount, pnl, date_str, note)
  values (public.new_text_id(), v_pos.participant_id, v_pos.league_id, case when v_status='LIQUIDATED' then '강제청산' else '포지션 청산' end, v_pos.symbol, v_pos.name, p_exit, v_returned, v_pnl, to_char(now(), 'MM-DD HH24:MI'), v_pos.lev || 'x ' || upper(v_pos.dir));
  return v_pnl;
end;
$$;

grant execute on function public.claim_league_reward(text,text) to authenticated;
grant execute on function public.place_spot_order(text,text,text,text,numeric,numeric) to authenticated;
grant execute on function public.open_future_position(text,text,text,text,numeric,numeric,numeric,numeric) to authenticated;
grant execute on function public.close_future_position(text,numeric) to authenticated;

-- Repair participants that were marked as claimed before cash was assigned.
update public.participants p
set cash = coalesce(l.initial_cash, 10000)
from public.leagues l
where p.league_id = l.id
  and p.reward_claimed = true
  and coalesce(p.cash, 0) = 0;

-- Remove accidental placeholder leagues that were created from the empty local state.
delete from public.leagues
where name = '리그 없음';

notify pgrst, 'reload schema';
