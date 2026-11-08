# Local verification — 8 November 2026

Release state: NOT DEPLOYED. Local results do not establish staging or production readiness.

## Results

- commission-runtime.mjs: 12 behavioral tests passed using PGlite 0.5.15 with synthetic auth/storage and parent schema. The actual commission migration applied successfully. Tests include fee/reversal amounts, duplicate retries, admin validation, policy activation guards, date rejection, ledger immutability, and preservation of the original signed agreement.
- orders-pagination.mjs: 4 mocked handler tests passed. All 1,205 ledger rows contributed to INR 9,950 net; a failed page returned an error without a partial total; unauthenticated and non-admin requests were rejected.
- addendum-archive-retry.mjs: 3 mocked handler tests passed with real pdf-lib 1.17.1 PDF generation. A failed archival RPC can resume after successful upload without overwriting signed bytes; different existing bytes are rejected.
- addendum-admin-pdf.mjs: 5 mocked handler tests passed, plus frontend JavaScript syntax parsing. PDF retrieval requires admin authorization, checks integrity, uses no-store, does not trigger approval, and refuses corrupt archives or repeat approval.

Total: 24 behavioral tests and a frontend syntax check. These are offline tests; OTP delivery, hosted Edge runtime, storage policies, end-to-end browser operation, live settlements and deployed data access remain unverified.

## Reproduce

Install @electric-sql/pglite@0.5.15, typescript@5.9.3 and pdf-lib@1.17.1 in an isolated checkout. Run each of the four .mjs files under mes-agreement/tests with Node.js. Test files use synthetic data and do not require Supabase credentials.

## Deployment blockers

The staging project snycybvewzuevlcuszya remains separate from production edpjkcatuiavqcqyvmau. The latest public-table inventory returned no tables. Security advisors returned no findings, which is not a release clearance for an empty project.

An earlier staging migration request was rejected by automatic security review without a detailed reason. No SQL Editor, alternate credentials or other execution route has been used to bypass that rejection. An authorized resolution of that restriction is required before hosted migration testing can proceed.

Further release work includes staging migrations and Edge deployment; OTP, PDF and prospective effective-date end-to-end tests; reconciliation of legacy 5% liabilities and new order fees/payments; and a verified production rollout. Existing signed agreements and historical production records must remain preserved.
