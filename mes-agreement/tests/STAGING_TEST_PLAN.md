# Staging test matrix — ₹10 commission

Do not run against production or existing signed sellers. Use a disposable staging database, service-role access through a trusted test harness, and two synthetic sellers with synthetic authenticated admin accounts.

## Prerequisites

1. Apply the reviewed additive migration in staging.
2. Create synthetic signed agreement v1 and seller identities.
3. Verify an addendum cannot be accepted without a confirmed auth email matching the seller's email.
4. Verify MES approval rejects missing PDF key or invalid SHA-256 hash.
5. After archiving a test signed PDF and valid hash, approve the addendum as an authenticated MES admin. Record its effective timestamp; never backdate it.
6. Post test orders with delivered dates **after** that effective timestamp. Use current-time timestamps; don't fabricate historic deliveries before activation.

## Expected cases

| Case | Steps | Expected |
| --- | --- | --- |
| First delivery | POST delivered A | ledger +10 |
| Duplicate delivery | POST delivered A again | ledger remains +10 |
| Full return | POST returned A with same delivery date and later return date | ledger +10,-10; net 0 |
| Duplicate full return | POST returned A again | net 0 |
| RTO | POST rto B with no delivery date | no ledger entry |
| Cancelled | POST cancelled C with no delivery date | no ledger entry |
| Fake delivered RTO | POST rto D with delivered date | rejected |
| Future delivery | POST delivered E with future date | rejected |
| Return before delivery | POST returned F with earlier return date | rejected |
| Return without delivery | POST returned G without delivery date | rejected |
| Return on new order | POST returned H with valid delivery and return dates | atomic +10,-10 |
| Refund then delivery | POST refunded H then delivered H | rejected |
| Changed delivery date | POST delivered A with different delivery date | rejected |
| Seller not opted in | POST delivered for second synthetic seller | rejected |
| Legacy pre-effective delivery | POST delivered before approval timestamp | rejected |
| Unknown actor | POST without authenticated MES admin | rejected by edge function |
| Repeated marketplace ID | Same seller + marketplace + order ID | single order row |
| Same ID different marketplace | Same seller, different marketplace | separate rows, reconcile business duplicates manually |
| Partial return | No full-return event; keep delivery charge | +10 |
| Signed legacy PDF | Inspect original agreement record | unchanged |
| Paid return credit | Reconcile refund after payment | credit carried forward or refunded without corrupting old settlement |

## Release-blocking gaps

- Email OTP seller login frontend is not integrated.
- The current public enrollment/sign function still writes version 1.0, and accepts an enrollment ID plus signer name without independent seller authentication. Do not market this as secure v2 signing.
- New seller v2 agreement signing and immutable server-side PDF archival are not implemented.
- MES approval API and administrative UI are not deployed.
- No staging integration results exist yet.
- No production migration has been applied.

No checkbox is considered passed without test logs and independently verified database rows.
