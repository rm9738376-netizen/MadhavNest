-- STAGING ONLY: synthetic parent tables needed to exercise the additive ₹10 migration.
-- Do not apply this file to production; it is not a copy of the production schema.
create table if not exists public.seller_users (
 id uuid primary key default gen_random_uuid(),
 auth_user_id uuid unique references auth.users(id),
 name text not null,
 email text not null unique,
 mobile text,
 status text not null default 'active',
 created_at timestamptz not null default now()
);
create table if not exists public.seller_agreements (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null unique references public.seller_users(id),
 version text not null default '1.0',
 terms_status text not null default 'pending'
  check (terms_status in ('pending','signed')),
 signed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.admin_users (
 auth_user_id uuid primary key references auth.users(id),
 email text not null,
 created_at timestamptz not null default now()
);
alter table public.seller_users enable row level security;
alter table public.seller_agreements enable row level security;
alter table public.admin_users enable row level security;
-- Intentionally no public read/write policies.
