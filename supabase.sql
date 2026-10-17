-- 在 Supabase Dashboard -> SQL Editor 中整份执行。
create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 100),
  description text not null default '' check (char_length(description) <= 500),
  starts_at timestamptz,
  ends_at timestamptz,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at is null or ends_at is null or starts_at <= ends_at)
);
create table if not exists public.candidates (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  photo_url text check (photo_url is null or char_length(photo_url) <= 2048),
  bio text not null default '' check (char_length(bio) <= 200),
  created_at timestamptz not null default now()
);
create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint one_vote_per_user_per_poll unique (poll_id, user_id)
);
create index if not exists candidates_poll_id_idx on public.candidates(poll_id);
create index if not exists votes_poll_id_idx on public.votes(poll_id);
create index if not exists votes_candidate_id_idx on public.votes(candidate_id);

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()));
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

create or replace function public.vote_candidate_matches_poll()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.candidates c where c.id = new.candidate_id and c.poll_id = new.poll_id) then
    raise exception 'Candidate does not belong to this poll';
  end if;
  if not exists (
    select 1 from public.polls p where p.id = new.poll_id and p.is_published = true
      and (p.starts_at is null or p.starts_at <= now())
      and (p.ends_at is null or p.ends_at >= now())
  ) then raise exception 'Poll is not open'; end if;
  if new.user_id <> (select auth.uid()) then raise exception 'Invalid voter'; end if;
  return new;
end; $$;
drop trigger if exists validate_vote_before_insert on public.votes;
create trigger validate_vote_before_insert before insert on public.votes
for each row execute function public.vote_candidate_matches_poll();

alter table public.admin_users enable row level security;
alter table public.polls enable row level security;
alter table public.candidates enable row level security;
alter table public.votes enable row level security;

-- Public may view published polls and their candidates; only admins can manage them.
drop policy if exists "published polls are readable" on public.polls;
create policy "published polls are readable" on public.polls for select to anon, authenticated using (is_published or public.is_admin());
drop policy if exists "admins manage polls" on public.polls;
create policy "admins manage polls" on public.polls for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "published candidates are readable" on public.candidates;
create policy "published candidates are readable" on public.candidates for select to anon, authenticated using (exists(select 1 from public.polls p where p.id = poll_id and (p.is_published or public.is_admin())));
drop policy if exists "admins manage candidates" on public.candidates;
create policy "admins manage candidates" on public.candidates for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- Each authenticated user can read only their own vote; aggregate counts are exposed via a safe view below.
drop policy if exists "users read own votes" on public.votes;
create policy "users read own votes" on public.votes for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists "users insert own vote" on public.votes;
create policy "users insert own vote" on public.votes for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "admins manage votes" on public.votes;
create policy "admins manage votes" on public.votes for delete to authenticated using (public.is_admin());
drop policy if exists "admins read admin list" on public.admin_users;
create policy "admins read admin list" on public.admin_users for select to authenticated using (public.is_admin());

-- Safe public aggregate: exposes totals by candidate, never voter identities.
create or replace view public.public_vote_counts with (security_invoker = false) as
select c.id as candidate_id, c.poll_id, count(v.id)::bigint as vote_count
from public.candidates c left join public.votes v on v.candidate_id = c.id
group by c.id, c.poll_id;
grant select on public.public_vote_counts to anon, authenticated;

-- IMPORTANT: After creating your account in Authentication -> Users, copy its UUID and run:
-- insert into public.admin_users (user_id) values ('YOUR_AUTH_USER_UUID');
