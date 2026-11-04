# Production release gates — ₹10 order model

## Critical findings from the current live code

1. `mes-public` signs an agreement when given only an enrollment UUID and a name. It does **not** verify control of the seller email/phone or an authenticated seller account. Do not expose addendum acceptance or v2 signing through this path; knowing/obtaining an enrollment UUID must not permit signing for another seller.
2. The existing browser creates agreement PDFs after signing, with the **client's current clock**, and does not persist a server-generated signed PDF/hash. A downloaded PDF alone cannot be relied on as immutable evidence of exactly what was accepted.
3. Existing admin settlement PUT always recomputes 5% of Net Sales. Order-ledger totals must be shown separately and must not be silently mixed with or overwrite historical 5% settlements.
4. The SQL draft and Edge Function draft have not been executed or tested against production. A previous production migration request was blocked by security checks; do not bypass the block.
5. The order ledger needs tests for late refunds, historical effective dates, duplicate orders, replacement identifiers, partial returns, already-paid invoices, and transition from legacy to new terms.
6. The SQL RPC uses `security invoker` and service-role-only EXECUTE; verify grants, RLS, and transaction behavior in staging before deploying.

## Required implementation sequence

- [ ] Obtain legal review for agreement v2.0 and addendum, including taxes, effective date, consent, and termination.
- [ ] Implement verified seller identity challenge (email OTP/magic link or authenticated seller session) and one-time server-issued signing token bound to seller + agreement version; record timestamp, IP/user-agent where lawful, exact terms hash and PDF hash. Do not rely on user-submitted seller ID alone.
- [ ] Add a server-side signed agreement snapshot with immutable version, start and end dates, and signed PDF retrieval. For existing sellers, addendum must preserve original 12-month end date.
- [ ] Fix initial v2 enrollment flow to persist version 2.0 before enabling v2 terms in the UI. Existing signed v1 rows must not be overwritten.
- [ ] Validate manual order events and ledger RPC atomically in a staging database with fake sellers, including repeated identical POSTs.
- [ ] Reconcile settlement logic: old 5% liabilities, new ₹10 ledger, refunds after payout, carry-forward credits, and GST if applicable.
- [ ] Review admin authentication, function deployment config, and RLS. Ensure no anonymous direct write path.
- [ ] Back up DB and signed records, run migrations in approved environment, deploy Edge Functions and UI together, run smoke tests, then publish.
- [ ] Verify live behavior and monitor failed events before announcing launch.

## Minimum acceptance tests

| Scenario | Expected |
| --- | --- |
| Delivered unique order | +₹10 once |
| Same order posted twice | Still +₹10 |
| Full refund after delivery | Net ₹0 |
| Duplicate refund | Net ₹0 |
| Cancelled/RTO before delivery | ₹0 |
| Partial return with fulfilled item | Remains ₹10 |
| Legacy seller without addendum | New order posting rejected |
| Order delivered before effective date | New flat charge rejected |
| Existing seller accepts addendum | Original expiry unchanged |
| Signed agreement already exists | Signed v1 record and PDF remain unchanged |
| Unauthenticated addendum attempt | Rejected |
| Paid order subsequently returned | Credit reconciled without negative constrained legacy settlement |

**Release status:** NOT DEPLOYED. Do not describe this feature as complete or live until all gates pass.

## Final release gate — 2026-11-04

- [x] Admin approval endpoint verifies actual private PDF bytes against stored SHA-256 before requesting approval (code only; not runtime-tested).
- [ ] **Blocker:** Signed PDF rendering must preserve the exact Unicode addendum text; current pdf-lib standard font path normalizes unsupported characters. A hash of the rendered PDF does not prove the legal wording matches the text accepted in the browser.
- [ ] **Blocker:** Confirm that the full signed PDF represents the correct seller identity, terms, acceptance timestamp and immutable evidence; review by legal counsel.
- [ ] **Blocker:** New-seller v2.0 agreement signing is not implemented. The existing public enrollment function still signs v1.0.
- [ ] **Blocker:** Run the SQL migration in a disposable staging environment and execute the full staging test matrix; inspect the real schema for column compatibility.
- [ ] **Blocker:** Verify that Edge Functions compile with the current Supabase runtime and that email OTP is configured.
- [ ] **Blocker:** Reconcile 5% legacy settlements and ₹10 order-ledger credits without double billing.
- [ ] **Blocker:** Obtain legal approval and authorized deployment approval; production migration was previously blocked and must not be bypassed.
- [ ] Deploy only after documented staging pass and rollback rehearsal.

No production launch is authorized by these commits.
