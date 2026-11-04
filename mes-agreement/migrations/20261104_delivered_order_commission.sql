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

-- Prevent unsigned/forged acceptance from activating a billing policy.
-- A privileged backend must verify seller identity and sign the addendum first.
create unique index if not exists one_commission_term_per_effective_date
 on public.seller_commission_terms(seller_id,effective_from);
create unique index if not exists one_addendum_per_original_version
 on public.seller_agreement_addenda(original_agreement_id,version);
alter table public.seller_agreement_addenda add constraint signed_addendum_complete
 check ((accepted_at is null and accepted_name is null) or (accepted_at is not null and nullif(trim(accepted_name),'') is not null));
-- Transactional manual-order posting; callable only by service_role.
-- The admin Edge Function must verify admin_users before invoking this RPC.
create or replace function public.mes_record_order(
 p_seller_id uuid,p_marketplace text,p_order_id text,p_status text,
 p_delivered_at timestamptz,p_returned_at timestamptz,p_actor uuid,p_notes text default ''
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare v_order public.seller_orders%rowtype;v_policy public.seller_commission_terms%rowtype;
 v_charged boolean;v_reversed boolean;v_now timestamptz:=now();
begin
 if p_marketplace not in ('Flipkart','Meesho') or p_status not in ('delivered','returned','refunded','cancelled','rto')
 or nullif(trim(p_order_id),'') is null or p_actor is null then raise exception 'Invalid order input';end if;
 select * into v_policy from public.seller_commission_terms
 where seller_id=p_seller_id and model='delivered_order_flat' and accepted_at is not null
 and effective_from<=coalesce(p_delivered_at,v_now)
 order by effective_from desc limit 1;
 if not found then raise exception 'Accepted ₹10 commission policy not effective for delivery date';end if;
 if p_status in ('delivered','returned','refunded') and p_delivered_at is null then raise exception 'Delivery date required';end if;
 if p_status in ('returned','refunded') and p_returned_at is null then raise exception 'Return date required';end if;
 if p_delivered_at is not null and p_delivered_at < v_policy.effective_from then raise exception 'Delivery predates accepted policy';end if;
 if p_delivered_at > v_now or p_returned_at > v_now then raise exception 'Future event date invalid';end if;
 if p_returned_at is not null and p_delivered_at is not null and p_returned_at < p_delivered_at then raise exception 'Return before delivery';end if;
 insert into public.seller_orders(seller_id,marketplace,marketplace_order_id,status,delivered_at,returned_at,notes,created_by)
 values(p_seller_id,p_marketplace,trim(p_order_id),p_status,p_delivered_at,p_returned_at,coalesce(p_notes,''),p_actor)
 on conflict(seller_id,marketplace,marketplace_order_id) do nothing;
 select * into v_order from public.seller_orders where seller_id=p_seller_id and marketplace=p_marketplace and marketplace_order_id=trim(p_order_id) for update;
 select exists(select 1 from public.order_commission_ledger where order_id=v_order.id and event_type='delivery_charge') into v_charged;
 select exists(select 1 from public.order_commission_ledger where order_id=v_order.id and event_type='return_reversal') into v_reversed;
 if v_reversed and p_status='delivered' then raise exception 'Reversed order cannot be recharged automatically';end if;
 if v_charged and p_status in ('cancelled','rto') then raise exception 'Previously delivered order requires return/refund adjustment';end if;
 if v_order.status in ('returned','refunded') and p_status not in ('returned','refunded') then raise exception 'Cannot undo return without reviewed correction';end if;
 if v_charged and v_order.delivered_at is distinct from p_delivered_at then raise exception 'Delivery date locked after charging';end if;
 if p_status in ('delivered','returned','refunded') then
  insert into public.order_commission_ledger(order_id,seller_id,event_type,amount,event_at,created_by)
  values(v_order.id,p_seller_id,'delivery_charge',10,p_delivered_at,p_actor) on conflict(order_id,event_type) do nothing;
 end if;
 if p_status in ('returned','refunded') then
  insert into public.order_commission_ledger(order_id,seller_id,event_type,amount,event_at,created_by)
  values(v_order.id,p_seller_id,'return_reversal',-10,p_returned_at,p_actor) on conflict(order_id,event_type) do nothing;
 end if;
 update public.seller_orders set status=p_status,delivered_at=p_delivered_at,returned_at=p_returned_at,notes=coalesce(p_notes,''),updated_at=v_now where id=v_order.id;
 return jsonb_build_object('order_id',v_order.id,'status',p_status);
end $$;
revoke all on function public.mes_record_order(uuid,text,text,text,timestamptz,timestamptz,uuid,text) from public,anon,authenticated;
grant execute on function public.mes_record_order(uuid,text,text,text,timestamptz,timestamptz,uuid,text) to service_role;
