-- Additive schema only. Existing 5% settlements and signed agreements remain unchanged.
create table if not exists public.seller_commission_terms (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.seller_users(id),
 model text not null check (model in ('net_sales_percentage','delivered_order_flat')),
 rate numeric(12,2) not null check (rate >= 0),
 effective_from timestamptz not null,
 accepted_at timestamptz,
 accepted_by uuid,
 agreement_id uuid references public.seller_agreements(id),
 addendum_reference text,
 created_at timestamptz not null default now(),
 constraint flat_rate_ten check (model <> 'delivered_order_flat' or rate = 10),
 constraint acceptance_required check (model <> 'delivered_order_flat' or (accepted_at is not null and addendum_reference is not null))
);
create index if not exists seller_commission_terms_lookup on public.seller_commission_terms(seller_id,effective_from desc);
create table if not exists public.seller_orders (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.seller_users(id),
 marketplace text not null check (marketplace in ('Flipkart','Meesho')),
 marketplace_order_id text not null check (length(trim(marketplace_order_id)) > 0),
 delivered_at timestamptz,
 returned_at timestamptz,
 status text not null check (status in ('delivered','returned','refunded','cancelled','rto')),
 notes text not null default '',
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (seller_id, marketplace, marketplace_order_id),
 constraint delivered_date_required check (status not in ('delivered','returned','refunded') or delivered_at is not null),
 constraint return_date_required check (status not in ('returned','refunded') or returned_at is not null)
);
create table if not exists public.order_commission_ledger (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.seller_orders(id),
 seller_id uuid not null references public.seller_users(id),
 event_type text not null check (event_type in ('delivery_charge','return_reversal')),
 amount numeric(12,2) not null,
 event_at timestamptz not null,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique (order_id,event_type),
 constraint ledger_amount check ((event_type = 'delivery_charge' and amount = 10) or (event_type = 'return_reversal' and amount = -10))
);
create table if not exists public.seller_agreement_addenda (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.seller_users(id),
 original_agreement_id uuid not null references public.seller_agreements(id),
 version text not null default '2.0',
 terms_text text not null,
 accepted_at timestamptz,
 accepted_name text,
 pdf_key text,
 pdf_hash text,
 created_at timestamptz not null default now()
);
alter table public.seller_commission_terms enable row level security;
alter table public.seller_orders enable row level security;
alter table public.order_commission_ledger enable row level security;
alter table public.seller_agreement_addenda enable row level security;
-- No client RLS policies: only privileged, server-side admin functions may write.
