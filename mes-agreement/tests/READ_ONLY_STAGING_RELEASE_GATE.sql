-- READ-ONLY staging release gate. Run ONLY after authorized staging migrations.
-- Does not create users, agreements, orders, policies or production changes.
-- A raised exception is a failed gate; do not deploy on failure.
DO $gate$
DECLARE
  missing text;
  bad_count bigint;
BEGIN
  SELECT string_agg(name, ', ') INTO missing
  FROM (VALUES
    ('seller_commission_terms'), ('seller_orders'),
    ('order_commission_ledger'), ('seller_agreement_addenda')
  ) AS expected(name)
  WHERE to_regclass('public.' || name) IS NULL;
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'Missing tables: %', missing; END IF;

  SELECT string_agg(name, ', ') INTO missing
  FROM (VALUES
    ('mes_record_order'), ('mes_accept_addendum'),
    ('mes_archive_addendum'), ('mes_approve_addendum')
  ) AS expected(name)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=expected.name
  );
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'Missing RPCs: %', missing; END IF;

  SELECT count(*) INTO bad_count FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public'
    AND c.relname IN ('seller_commission_terms','seller_orders',
                      'order_commission_ledger','seller_agreement_addenda')
    AND NOT c.relrowsecurity;
  IF bad_count <> 0 THEN RAISE EXCEPTION '% commission tables lack RLS', bad_count; END IF;

  SELECT count(*) INTO bad_count FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname IN ('mes_record_order','mes_accept_addendum',
                      'mes_archive_addendum','mes_approve_addendum')
    AND (has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE'));
  IF bad_count <> 0 THEN RAISE EXCEPTION '% RPCs callable by public clients', bad_count; END IF;

  SELECT count(*) INTO bad_count FROM public.order_commission_ledger l
  WHERE (l.event_type='delivery_charge' AND l.amount<>10)
     OR (l.event_type='return_reversal' AND l.amount<>-10);
  IF bad_count <> 0 THEN RAISE EXCEPTION '% ledger entries have incorrect amounts', bad_count; END IF;

  SELECT count(*) INTO bad_count FROM (
    SELECT order_id, sum(amount) AS total
    FROM public.order_commission_ledger GROUP BY order_id
  ) t WHERE t.total NOT IN (0,10);
  IF bad_count <> 0 THEN RAISE EXCEPTION '% orders have invalid net commission', bad_count; END IF;

  SELECT count(*) INTO bad_count FROM public.seller_commission_terms t
  WHERE t.model='delivered_order_flat' AND NOT EXISTS (
    SELECT 1 FROM public.seller_agreement_addenda a
    WHERE a.id::text=t.addendum_reference
      AND a.seller_id=t.seller_id
      AND a.mes_approved_at IS NOT NULL
      AND a.pdf_key IS NOT NULL
      AND a.pdf_hash ~ '^[0-9a-f]{64}$'
      AND t.effective_from >= a.mes_approved_at
  );
  IF bad_count <> 0 THEN RAISE EXCEPTION '% flat policies lack approved evidence', bad_count; END IF;
  RAISE NOTICE 'PASS: schema, RLS, RPC permissions, ledger and approval invariants';
END $gate$;

-- Follow with transactional behavioral tests in an isolated staging fixture:
-- 1 delivered=+10; repeat=+0; complete return=-10; repeat reversal=+0.
-- 2 partial return retains +10; cancelled/RTO=0.
-- 3 delivery before approval rejected; unapproved seller rejected.
-- 4 old signed 5%% agreement unchanged; no existing settlements modified.
-- 5 unauthorized caller rejected; signed PDF hash checked against stored bytes.
-- 6 concurrent duplicate delivery requests result in exactly one charge.
-- DO NOT use synthetic fixture identities on production.
