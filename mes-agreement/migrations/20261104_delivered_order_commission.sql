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
 -- Defense in depth: the RPC itself requires a registered MES admin actor,
 -- even when invoked through a service-role backend.
 if not exists(select 1 from public.admin_users where auth_user_id=p_actor)
 then raise exception 'MES admin actor required';end if;
 if p_marketplace not in ('Flipkart','Meesho') or p_status not in ('delivered','returned','refunded','cancelled','rto')
 or nullif(trim(p_order_id),'') is null or p_actor is null then raise exception 'Invalid order input';end if;
 -- Cancellation and undelivered RTO are recorded at zero fee, even if no flat-rate
 -- policy existed at the event time. Delivered events require the approved policy.
 if p_status in ('delivered','returned','refunded') then
  select * into v_policy from public.seller_commission_terms
  where seller_id=p_seller_id and model='delivered_order_flat' and accepted_at is not null
  and effective_from<=p_delivered_at
  and exists (select 1 from public.seller_agreement_addenda a
   where a.id::text = seller_commission_terms.addendum_reference
   and a.seller_id = seller_commission_terms.seller_id
   and a.mes_approved_at is not null
   and a.pdf_key is not null and a.pdf_hash ~ '^[0-9a-f]{64}
  if not found then raise exception 'Accepted ₹10 commission policy not effective for delivery date';end if;
 end if;
 if p_status in ('delivered','returned','refunded') and p_delivered_at is null then raise exception 'Delivery date required';end if;
 if p_status in ('returned','refunded') and p_returned_at is null then raise exception 'Return date required';end if;
 if p_delivered_at is not null and p_delivered_at < v_policy.effective_from then raise exception 'Delivery predates accepted policy';end if;
 if p_delivered_at > v_now or p_returned_at > v_now then raise exception 'Future event date invalid';end if;
 if p_status in ('cancelled','rto') and (p_delivered_at is not null or p_returned_at is not null)
 then raise exception 'Cancelled or RTO orders must not include delivery or return dates';end if;
 -- 'returned' and 'refunded' mean a COMPLETE return/refund, not a partial one.
 -- Partial returns must remain 'delivered' so the original INR 10 fee is retained.
 -- Never post a reversal for partial fulfillment.
 if p_status='delivered' and p_returned_at is not null
 then raise exception 'Delivered orders cannot include a return date';end if;
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
 -- Once a reversal is posted, its accounting date and terminal status are immutable.
 -- Corrections must use a separately audited adjustment workflow.
 if v_reversed and (v_order.returned_at is distinct from p_returned_at
  or v_order.status is distinct from p_status)
 then raise exception 'Reversed order evidence is locked; reviewed adjustment required';end if;
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

-- Accounting entries are append-only: a correction must be a separately audited
-- adjustment, never a silent UPDATE or DELETE of original charges/reversals.
create or replace function public.mes_block_ledger_mutation()
returns trigger language plpgsql security invoker set search_path=public as $
begin
 raise exception 'Commission ledger is append-only; use an audited adjustment workflow';
end $;
drop trigger if exists mes_commission_ledger_immutable on public.order_commission_ledger;
create trigger mes_commission_ledger_immutable
 before update or delete on public.order_commission_ledger
 for each row execute function public.mes_block_ledger_mutation();
revoke all on function public.mes_block_ledger_mutation() from public,anon,authenticated;

-- Seller identity is checked again inside the transaction. No browser-supplied seller ID.
-- Signing an addendum alone does not activate new billing: MES must countersign.
alter table public.seller_agreement_addenda
 add column if not exists seller_auth_user_id uuid references auth.users(id),
 add column if not exists mes_approved_at timestamptz,
 add column if not exists mes_approved_by uuid references auth.users(id);
create or replace function public.mes_accept_addendum(p_actor uuid,p_terms text,p_signer text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_email text;v_seller uuid;v_agreement uuid;v_id uuid;v_accepted_at timestamptz;v_existing public.seller_agreement_addenda%rowtype;
begin
 select lower(email) into v_email from auth.users
 where id=p_actor and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verified email sign-in required';end if;
 select id into v_seller from public.seller_users where lower(email)=v_email;
 if v_seller is null then raise exception 'No seller registered with verified email';end if;
 select id into v_agreement from public.seller_agreements
 where seller_id=v_seller and terms_status='signed';
 if v_agreement is null then raise exception 'Signed original agreement required';end if;
 if nullif(trim(p_signer),'') is null or length(p_signer)>200 or length(p_terms)<100
 then raise exception 'Valid signatory and terms required';end if;
 select * into v_existing from public.seller_agreement_addenda
 where original_agreement_id=v_agreement and version='2.0' for update;
 if found then
  -- Safe archival retry: only the original verified signer with identical terms
  -- can resume; a signed or approved addendum cannot be replaced or altered.
  if v_existing.seller_auth_user_id is distinct from p_actor
   or v_existing.terms_text is distinct from p_terms
   or v_existing.accepted_name is distinct from trim(p_signer)
  then raise exception 'Existing addendum details differ; contact support';end if;
  return jsonb_build_object('addendum_id',v_existing.id,
   'status',case when v_existing.mes_approved_at is not null then 'active'
    when v_existing.pdf_key is not null then 'awaiting_mes_approval'
    else 'awaiting_pdf_archive' end,
   'archived',v_existing.pdf_key is not null,'accepted_at',v_existing.accepted_at);
 end if;
 insert into public.seller_agreement_addenda
 (seller_id,original_agreement_id,version,terms_text,accepted_at,accepted_name,seller_auth_user_id)
 values(v_seller,v_agreement,'2.0',p_terms,now(),trim(p_signer),p_actor)
 returning id,accepted_at into v_id,v_accepted_at;
 return jsonb_build_object('addendum_id',v_id,'status','awaiting_mes_approval','accepted_at',v_accepted_at);
end $$;
revoke all on function public.mes_accept_addendum(uuid,text,text) from public,anon,authenticated;
grant execute on function public.mes_accept_addendum(uuid,text,text) to service_role;

-- MES countersignature is the sole way to activate the flat-fee policy.
-- Block approval until the signed document is archived and hashed.
create or replace function public.mes_approve_addendum(
 p_addendum_id uuid,p_admin_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_addendum public.seller_agreement_addenda%rowtype;v_effective timestamptz:=clock_timestamp();
begin
 if not exists(select 1 from public.admin_users where auth_user_id=p_admin_id)
 then raise exception 'MES admin approval required';end if;
 select * into v_addendum from public.seller_agreement_addenda
 where id=p_addendum_id for update;
 if not found then raise exception 'Addendum not found';end if;
 if v_addendum.accepted_at is null or v_addendum.seller_auth_user_id is null
 then raise exception 'Seller has not verified and accepted';end if;
 if v_addendum.mes_approved_at is not null then raise exception 'Already approved';end if;
 if nullif(trim(v_addendum.pdf_key),'') is null
 or v_addendum.pdf_hash !~ '^[0-9a-f]{64}$'
 then raise exception 'Signed addendum PDF and SHA-256 hash must be archived before approval';end if;
 if not exists(select 1 from public.seller_agreements
 where id=v_addendum.original_agreement_id and seller_id=v_addendum.seller_id
 and terms_status='signed') then raise exception 'Original signed agreement missing';end if;
 insert into public.seller_commission_terms
 (seller_id,model,rate,effective_from,accepted_at,accepted_by,agreement_id,addendum_reference)
 values(v_addendum.seller_id,'delivered_order_flat',10,v_effective,
 v_addendum.accepted_at,v_addendum.seller_auth_user_id,
 v_addendum.original_agreement_id,v_addendum.id::text);
 update public.seller_agreement_addenda set mes_approved_at=v_effective,
 mes_approved_by=p_admin_id where id=v_addendum.id;
 return jsonb_build_object('addendum_id',v_addendum.id,'effective_from',v_effective,'status','active');
end $$;
revoke all on function public.mes_approve_addendum(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mes_approve_addendum(uuid,uuid) to service_role;

-- Private archive: service-role-only access; do not expose public signed documents.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mes-signed-addenda','mes-signed-addenda',false,1048576,array['application/pdf'])
on conflict(id) do nothing;

-- Immutable signed document reference: archive evidence may be set once.
create or replace function public.mes_archive_addendum(
 p_addendum_id uuid,p_actor uuid,p_pdf_key text,p_pdf_hash text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_addendum public.seller_agreement_addenda%rowtype;
begin
 select * into v_addendum from public.seller_agreement_addenda
 where id=p_addendum_id for update;
 if not found or v_addendum.seller_auth_user_id is distinct from p_actor
 then raise exception 'Addendum not found for authenticated seller';end if;
 if v_addendum.accepted_at is null or v_addendum.mes_approved_at is not null
 then raise exception 'Addendum not eligible for archival';end if;
 if v_addendum.pdf_key is not null or v_addendum.pdf_hash is not null
 then raise exception 'Signed document already archived';end if;
 if p_pdf_key <> ('addenda/'||p_addendum_id::text||'.pdf')
 or p_pdf_hash !~ '^[0-9a-f]{64}$'
 then raise exception 'Invalid signed document reference';end if;
 update public.seller_agreement_addenda
 set pdf_key=p_pdf_key,pdf_hash=p_pdf_hash where id=p_addendum_id;
 return jsonb_build_object('addendum_id',p_addendum_id,'archived',true);
end $$;
revoke all on function public.mes_archive_addendum(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mes_archive_addendum(uuid,uuid,text,text) to service_role;
)
  order by effective_from desc limit 1;
  if not found then raise exception 'Accepted ₹10 commission policy not effective for delivery date';end if;
 end if;
 if p_status in ('delivered','returned','refunded') and p_delivered_at is null then raise exception 'Delivery date required';end if;
 if p_status in ('returned','refunded') and p_returned_at is null then raise exception 'Return date required';end if;
 if p_delivered_at is not null and p_delivered_at < v_policy.effective_from then raise exception 'Delivery predates accepted policy';end if;
 if p_delivered_at > v_now or p_returned_at > v_now then raise exception 'Future event date invalid';end if;
 if p_status in ('cancelled','rto') and (p_delivered_at is not null or p_returned_at is not null)
 then raise exception 'Cancelled or RTO orders must not include delivery or return dates';end if;
 -- 'returned' and 'refunded' mean a COMPLETE return/refund, not a partial one.
 -- Partial returns must remain 'delivered' so the original INR 10 fee is retained.
 -- Never post a reversal for partial fulfillment.
 if p_status='delivered' and p_returned_at is not null
 then raise exception 'Delivered orders cannot include a return date';end if;
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
 -- Once a reversal is posted, its accounting date and terminal status are immutable.
 -- Corrections must use a separately audited adjustment workflow.
 if v_reversed and (v_order.returned_at is distinct from p_returned_at
  or v_order.status is distinct from p_status)
 then raise exception 'Reversed order evidence is locked; reviewed adjustment required';end if;
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

-- Seller identity is checked again inside the transaction. No browser-supplied seller ID.
-- Signing an addendum alone does not activate new billing: MES must countersign.
alter table public.seller_agreement_addenda
 add column if not exists seller_auth_user_id uuid references auth.users(id),
 add column if not exists mes_approved_at timestamptz,
 add column if not exists mes_approved_by uuid references auth.users(id);
create or replace function public.mes_accept_addendum(p_actor uuid,p_terms text,p_signer text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_email text;v_seller uuid;v_agreement uuid;v_id uuid;v_accepted_at timestamptz;v_existing public.seller_agreement_addenda%rowtype;
begin
 select lower(email) into v_email from auth.users
 where id=p_actor and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verified email sign-in required';end if;
 select id into v_seller from public.seller_users where lower(email)=v_email;
 if v_seller is null then raise exception 'No seller registered with verified email';end if;
 select id into v_agreement from public.seller_agreements
 where seller_id=v_seller and terms_status='signed';
 if v_agreement is null then raise exception 'Signed original agreement required';end if;
 if nullif(trim(p_signer),'') is null or length(p_signer)>200 or length(p_terms)<100
 then raise exception 'Valid signatory and terms required';end if;
 select * into v_existing from public.seller_agreement_addenda
 where original_agreement_id=v_agreement and version='2.0' for update;
 if found then
  -- Safe archival retry: only the original verified signer with identical terms
  -- can resume; a signed or approved addendum cannot be replaced or altered.
  if v_existing.seller_auth_user_id is distinct from p_actor
   or v_existing.terms_text is distinct from p_terms
   or v_existing.accepted_name is distinct from trim(p_signer)
  then raise exception 'Existing addendum details differ; contact support';end if;
  return jsonb_build_object('addendum_id',v_existing.id,
   'status',case when v_existing.mes_approved_at is not null then 'active'
    when v_existing.pdf_key is not null then 'awaiting_mes_approval'
    else 'awaiting_pdf_archive' end,
   'archived',v_existing.pdf_key is not null,'accepted_at',v_existing.accepted_at);
 end if;
 insert into public.seller_agreement_addenda
 (seller_id,original_agreement_id,version,terms_text,accepted_at,accepted_name,seller_auth_user_id)
 values(v_seller,v_agreement,'2.0',p_terms,now(),trim(p_signer),p_actor)
 returning id,accepted_at into v_id,v_accepted_at;
 return jsonb_build_object('addendum_id',v_id,'status','awaiting_mes_approval','accepted_at',v_accepted_at);
end $$;
revoke all on function public.mes_accept_addendum(uuid,text,text) from public,anon,authenticated;
grant execute on function public.mes_accept_addendum(uuid,text,text) to service_role;

-- MES countersignature is the sole way to activate the flat-fee policy.
-- Block approval until the signed document is archived and hashed.
create or replace function public.mes_approve_addendum(
 p_addendum_id uuid,p_admin_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_addendum public.seller_agreement_addenda%rowtype;v_effective timestamptz:=clock_timestamp();
begin
 if not exists(select 1 from public.admin_users where auth_user_id=p_admin_id)
 then raise exception 'MES admin approval required';end if;
 select * into v_addendum from public.seller_agreement_addenda
 where id=p_addendum_id for update;
 if not found then raise exception 'Addendum not found';end if;
 if v_addendum.accepted_at is null or v_addendum.seller_auth_user_id is null
 then raise exception 'Seller has not verified and accepted';end if;
 if v_addendum.mes_approved_at is not null then raise exception 'Already approved';end if;
 if nullif(trim(v_addendum.pdf_key),'') is null
 or v_addendum.pdf_hash !~ '^[0-9a-f]{64}$'
 then raise exception 'Signed addendum PDF and SHA-256 hash must be archived before approval';end if;
 if not exists(select 1 from public.seller_agreements
 where id=v_addendum.original_agreement_id and seller_id=v_addendum.seller_id
 and terms_status='signed') then raise exception 'Original signed agreement missing';end if;
 insert into public.seller_commission_terms
 (seller_id,model,rate,effective_from,accepted_at,accepted_by,agreement_id,addendum_reference)
 values(v_addendum.seller_id,'delivered_order_flat',10,v_effective,
 v_addendum.accepted_at,v_addendum.seller_auth_user_id,
 v_addendum.original_agreement_id,v_addendum.id::text);
 update public.seller_agreement_addenda set mes_approved_at=v_effective,
 mes_approved_by=p_admin_id where id=v_addendum.id;
 return jsonb_build_object('addendum_id',v_addendum.id,'effective_from',v_effective,'status','active');
end $$;
revoke all on function public.mes_approve_addendum(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mes_approve_addendum(uuid,uuid) to service_role;

-- Private archive: service-role-only access; do not expose public signed documents.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mes-signed-addenda','mes-signed-addenda',false,1048576,array['application/pdf'])
on conflict(id) do nothing;

-- Immutable signed document reference: archive evidence may be set once.
create or replace function public.mes_archive_addendum(
 p_addendum_id uuid,p_actor uuid,p_pdf_key text,p_pdf_hash text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_addendum public.seller_agreement_addenda%rowtype;
begin
 select * into v_addendum from public.seller_agreement_addenda
 where id=p_addendum_id for update;
 if not found or v_addendum.seller_auth_user_id is distinct from p_actor
 then raise exception 'Addendum not found for authenticated seller';end if;
 if v_addendum.accepted_at is null or v_addendum.mes_approved_at is not null
 then raise exception 'Addendum not eligible for archival';end if;
 if v_addendum.pdf_key is not null or v_addendum.pdf_hash is not null
 then raise exception 'Signed document already archived';end if;
 if p_pdf_key <> ('addenda/'||p_addendum_id::text||'.pdf')
 or p_pdf_hash !~ '^[0-9a-f]{64}$'
 then raise exception 'Invalid signed document reference';end if;
 update public.seller_agreement_addenda
 set pdf_key=p_pdf_key,pdf_hash=p_pdf_hash where id=p_addendum_id;
 return jsonb_build_object('addendum_id',p_addendum_id,'archived',true);
end $$;
revoke all on function public.mes_archive_addendum(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mes_archive_addendum(uuid,uuid,text,text) to service_role;
