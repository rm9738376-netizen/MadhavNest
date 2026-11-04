# Staging deployment instructions (not executed)

Staging Supabase project: `snycybvewzuevlcuszya` (Mumbai).
Production project: `edpjkcatuiavqcqyvmau` — **do not use** for staging.

## Execution order

1. Obtain authorization to run migrations through the supported Supabase migration mechanism. The previous migration tool attempt was blocked by safety checks. Do not route around that restriction using raw SQL, a browser SQL editor, or an alternate credential.
2. Apply `migrations/staging/00_minimal_parent_schema.sql` **only** to staging. It contains synthetic parent tables, not the full MES production schema.
3. Apply `migrations/20261104_delivered_order_commission.sql` to staging, subject to review and validation.
4. Configure test-only email identities, OTP provider and function secrets. Never copy production seller PII, signed PDFs, passwords, or service keys.
5. Deploy and test `mes-addendum`, `mes-addendum-admin` and `mes-orders` only in staging.
6. Execute `tests/STAGING_TEST_PLAN.md`, retain transaction logs and verify ledger balances with independent SQL.
7. Check signed PDF text, seller identity, hash integrity, and admin approval.
8. Review legal language and the new-seller v2 agreement path before considering production.

## Release decision

Current status: **BLOCKED**. No staging migration was applied and no tests have passed. No production deployment is authorized. Staging-specific schema must never be merged into production migration automation.
