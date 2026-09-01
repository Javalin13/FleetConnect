# r056 Phase G-I — Data + Auth Migration Mapping (Split per Lux 7aac5aa §7/§8)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux 7aac5aa acceptance)
**Source project:** `rreqjjrmvytnwnsidmqi` (legacy, post-cutover read-only)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, post-Phase G apply)

---

## Critical change from prior round (per Lux 7aac5aa §7/§8)

This document **splits application data migration from auth migration**.
They have different execution contracts and different default paths.

- **Application data migration** (13 core tables): supported CSV /
  pg_dump / `\copy` path with FK/integrity checks
- **Auth migration** (`auth.users` + `auth.identities`): DEFAULT is
  re-onboarding / password reset. Raw CSV import is NOT the
  canonical path. (Lux §8: "no direct CSV-style auth migration is
  considered safe until an approved Supabase-compatible method is
  factually established.")

---

## Part 1 — Application data migration (13 core tables)

### 1.1 Source tables (13 ops tables on legacy)

| # | Table | Notes |
|---|-------|-------|
| T1 | `bookings` | PK: TEXT; FKs to customers/partners/drivers; largest table |
| T2 | `customers` | PK: TEXT; FK to auth.users |
| T3 | `partners` | PK: BIGSERIAL/BIGINT; FK to auth.users |
| T4 | `drivers` | PK: UUID; FK to auth.users + partners |
| T5 | `account_requests` | Pre-customer state |
| T6 | `payments` | Stripe payment intent linkage |
| T7 | `pricing_profiles` | Rate config; small |
| T8 | `fixed_routes` | Pre-priced routes; small |
| T9 | `invoices` | PDF generation linkage |
| T10 | `settlements` | Partner payouts |
| T11 | `ride_reviews` | Customer reviews |
| T12 | `refunds` | Stripe refund linkage |
| T13 | `transaction_ledger` | Audit-grade financial ledger; high integrity |

### 1.2 Founder export paths (per Lux §7 — supported authenticated paths only)

**Path A1: Dashboard SQL Editor result export (small tables, ~1000 rows)**

For each small table (T5, T6, T7, T8, T11):
1. Open legacy Dashboard → SQL Editor
2. Run: `SELECT * FROM public.<table> ORDER BY <pk> LIMIT 1000;`
3. Click the Dashboard "Export" button on the result grid → CSV
4. Download the CSV
5. Repeat per table

**Path A2: Dashboard Table Editor export (medium tables, ~10K rows)**

For medium tables (T2, T3, T4, T9, T10, T12):
1. Open legacy Dashboard → Table Editor → `<table>`
2. Click "..." menu → "Export" → CSV
3. Download the CSV
4. Repeat per table

**Path A3: pg_dump / psql `\copy` from Founder-authenticated local (large tables)**

For large tables (T1 bookings, T13 transaction_ledger):
1. Founder has the legacy DB connection string stored in 1Password
2. From Founder's authenticated local environment:
   ```bash
   pg_dump "$LEGACY_DB_URL" \
     --table=public.bookings \
     --table=public.transaction_ledger \
     --data-only --no-owner --column-inserts \
     > fleetconnect-legacy-data-$(date +%Y%m%d).sql
   ```
   `$LEGACY_DB_URL` is in Founder's local secret store, never in
   chat/Bridge/evidence/repo.

**Path A4: NOT USED — server-side `COPY TO '/tmp/...'` is rejected**

Per Lux 7aac5aa §7, server-side `COPY ... TO '/tmp/<file>'` is not
a reliable Dashboard export contract on managed Supabase. Do NOT
use this path. Use Path A1, A2, or A3 only.

### 1.3 Founder → PRIME handoff

After Founder exports the CSVs/SQL, the handoff mechanism is:
- Supabase Storage private bucket with signed URL (Founder uploads,
  PRIME downloads)
- OR local rsync over a secure channel

**NOT chat, NOT email, NOT Bridge, NOT the public repo.**

### 1.4 PRIME import procedure (after Wave 1 schema applied)

PRIME uses `psql \copy` (client-side) to import the CSVs. Order
respects FK dependencies:

```bash
# 1. Reference data first (no FKs)
psql "$NEW_DB_URL" -c "\\COPY pricing_profiles   FROM '/tmp/fc-pricing.csv'   CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY fixed_routes       FROM '/tmp/fc-routes.csv'    CSV HEADER"

# 2. Master data (FK to auth.users — but auth.users is handled separately in Part 2)
psql "$NEW_DB_URL" -c "\\COPY customers FROM '/tmp/fc-customers.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY partners  FROM '/tmp/fc-partners.csv'  CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY drivers   FROM '/tmp/fc-drivers.csv'    CSV HEADER"

# 3. Operational data (FKs to master data)
psql "$NEW_DB_URL" -c "\\COPY bookings            FROM '/tmp/fc-bookings.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY payments            FROM '/tmp/fc-payments.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY invoices            FROM '/tmp/fc-invoices.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY settlements         FROM '/tmp/fc-settlements.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY ride_reviews        FROM '/tmp/fc-reviews.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY refunds             FROM '/tmp/fc-refunds.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY transaction_ledger  FROM '/tmp/fc-tx.csv' CSV HEADER"
psql "$NEW_DB_URL" -c "\\COPY account_requests    FROM '/tmp/fc-acct-req.csv' CSV HEADER"
```

### 1.5 Post-import verification

```sql
-- Row count parity (must match legacy within ±0 for every table)
SELECT 'customers' tbl, count(*) FROM customers
UNION ALL SELECT 'partners',  count(*) FROM partners
UNION ALL SELECT 'drivers',   count(*) FROM drivers
UNION ALL SELECT 'bookings',  count(*) FROM bookings
UNION ALL SELECT 'payments',  count(*) FROM payments
UNION ALL SELECT 'invoices',  count(*) FROM invoices
UNION ALL SELECT 'settlements', count(*) FROM settlements
UNION ALL SELECT 'ride_reviews', count(*) FROM ride_reviews
UNION ALL SELECT 'refunds',   count(*) FROM refunds
UNION ALL SELECT 'transaction_ledger', count(*) FROM transaction_ledger
UNION ALL SELECT 'account_requests', count(*) FROM account_requests
ORDER BY tbl;

-- FK integrity (must be 0 orphans)
SELECT 'orphan customer' issue, count(*) FROM customers c
  WHERE user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = c.user_id);
-- (Repeat for partners, drivers if they have user_id)

-- For application-only tables (no auth.users dependency yet), the
-- check is on master data FKs:
SELECT 'orphan booking' issue, count(*) FROM bookings b
  WHERE customer_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.id = b.customer_id);
```

**Critical: `user_id` FKs WILL fail after re-onboarding (see Part 2).**
The Founder + PRIME must decide between:
- (A) Migrate application data with NULL `user_id`, re-link by email
  during re-onboarding
- (B) Migrate application data with the OLD `user_id` UUID preserved
  in a new `legacy_user_id` column (audit trail), NULL out the
  `user_id` FK column

**PRIME recommendation:** Option B (preserves the link for audit;
cleanly NULLs the broken FKs; lets the re-onboarding flow set the
new `user_id` after each user re-verifies).

---

## Part 2 — Auth migration (DEFAULT: re-onboarding; NOT raw CSV import)

### 2.1 What's in `auth.users` (legacy)

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `email` | TEXT | UNIQUE |
| `encrypted_password` | TEXT | bcrypt hash; project-specific salt risk |
| `raw_app_meta_data` | JSONB | App metadata |
| `raw_user_meta_data` | JSONB | User metadata |
| `email_confirmed_at` | TIMESTAMPTZ | Email verification status |
| `last_sign_in_at` | TIMESTAMPTZ | Last sign-in |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

Plus `auth.identities` (OAuth provider linkages) keyed by `user_id`.

### 2.2 DEFAULT: Controlled re-onboarding / password reset

**Why this is the default (per Lux 7aac5aa §8):**

1. Legacy `auth.users` hashes may be salted with a project-specific
   bcrypt salt that does not survive cross-project import
2. `auth.identities` (Google OAuth, etc.) rows have provider-specific
   invariants not preserved by naive CSV import
3. Supabase Auth version drift between legacy and new projects is
   undocumented and may break token verification
4. The operational user set is small (operators + a few dozen
   partners/drivers/customers); re-onboarding is operationally
   feasible

**Founder authenticated actions (re-onboarding flow):**

1. Inventory current users from legacy (any supported authenticated
   read path — Path A1 SQL Editor):
   ```sql
   SELECT id, email, raw_user_meta_data->>'role' AS role,
          email_confirmed_at IS NOT NULL AS email_verified
   FROM auth.users
   ORDER BY created_at;
   ```
2. Export the inventory to CSV (Path A1 Dashboard result export).
3. For each operator / partner / driver: trigger a password-reset
   email from the new project (Dashboard → Authentication → Users
   → select user → "Send recovery email")
4. For each customer: send a "your account is on the new platform,
   please re-set your password" email from the new project
5. Document the old → new user-id mapping in
   `evidence/r056-phase-g-auth-user-id-mapping.md`:
   - PRIME prepares the template
   - Founder fills the actuals
6. After each user re-verifies, application tables' `user_id` is
   updated from NULL (or `legacy_user_id`) to the new `auth.users.id`
   (handled by application logic at first login)

**Operational model after re-onboarding:**

```
Legacy auth.users (UUID v1)        New auth.users (UUID v2)
+--------------------+             +--------------------+
| id = aaaa-...      |             | id = zzzz-...      |
| email = a@b.com   | --email-->  | email = a@b.com    |
| hash = bcrypt(...) |   (reset)   | hash = bcrypt(...) |
+--------------------+             +--------------------+
         |                                  |
         v                                  v
   legacy_user_id                     user_id (new)
   (audit column)                     (FK after re-onboard)
```

### 2.3 EXCEPTION: raw `auth.users` / `auth.identities` import

**Use ONLY if:**
- (a) Re-onboarding is operationally infeasible AND
- (b) Founder has authenticated access to legacy `auth` schema
  (e.g. service_role via Founder-authenticated SQL Editor) AND
- (c) PRIME has verified against current Supabase docs that a
  supported cross-project auth transfer procedure exists AND
- (d) Lux has explicitly approved the import (per Lux §8)

**If all four conditions hold:**

1. Founder exports `auth.users` schema (without hashes initially) via
   SQL Editor result export (Path A1)
2. PRIME checks current Supabase Auth docs for the supported
   cross-project auth transfer procedure
3. If the docs describe a supported procedure, Founder executes it
   via Dashboard + the documented steps (NOT a raw CSV import)
4. If the docs do NOT describe a supported procedure, the default
   (re-onboarding) is used

**PRIME does NOT import raw `auth.users` / `auth.identities` CSVs
into the new project. This is a hard rule per Lux 7aac5aa §8.**

### 2.4 What this section does NOT do

- ❌ Does NOT prescribe `COPY ... TO '/tmp/...'` for auth export
- ❌ Does NOT prescribe `psql \copy` import of raw `auth.users` CSV
- ❌ Does NOT have PRIME handle password hashes directly
- ❌ Does NOT claim direct CSV import into `auth.users` is safe

---

## Part 3 — Auth user-id mapping (per Lux 7aac5aa §8)

Application tables (`customers`, `partners`, `drivers`, `bookings`)
have `user_id` columns that link to `auth.users.id`. After
re-onboarding, the new `user_id` values are different from the
legacy values.

**PRIME-prepared template:** `evidence/r056-phase-g-auth-user-id-mapping.md`
(Founder fills the actuals after Wave 4B)

**Format:**

```csv
legacy_user_id,legacy_email,new_user_id,new_email,re_onboard_status
aaaa-bbbb-...,ops@fleetconnect.be,zzzz-yyyy-...,ops@fleetconnect.be,RESET_SENT
...
```

**Application tables handling (Option B recommended):**

PRIME adds a `legacy_user_id UUID` column to each of `customers`,
`partners`, `drivers`, `bookings` via a small additive migration
(e.g. `20260901000001_legacy_user_id_audit_column.sql`):

```sql
-- PRIME-prepared additive migration (NOT yet committed; awaiting Lux review)
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS legacy_user_id UUID;
ALTER TABLE public.partners  ADD COLUMN IF NOT EXISTS legacy_user_id UUID;
ALTER TABLE public.drivers   ADD COLUMN IF NOT EXISTS legacy_user_id UUID;
ALTER TABLE public.bookings  ADD COLUMN IF NOT EXISTS legacy_user_id UUID;

CREATE INDEX IF NOT EXISTS idx_customers_legacy_user_id ON public.customers(legacy_user_id);
CREATE INDEX IF NOT EXISTS idx_partners_legacy_user_id  ON public.partners(legacy_user_id);
CREATE INDEX IF NOT EXISTS idx_drivers_legacy_user_id   ON public.drivers(legacy_user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_legacy_user_id  ON public.bookings(legacy_user_id);
```

**PRIME does NOT auto-create this migration in this round** — it
should be added in the next round after Lux review of the auth
migration contract.

---

## What this document does NOT cover

- Storage objects (per legacy probe, anon-readable buckets are
  empty; private buckets need separate audit)
- Realtime channel subscriptions (drop on cutover; clients re-subscribe)
- Edge function runtime state (in-flight IMAP IDLE sessions
  dropped by design)
- Webhook in-flight events (Stripe events in flight at cutover
  time may need re-trigger; Founder reviews Stripe Dashboard
  post-cutover)

---

## LUX — SYNC NEEDED

Five items to confirm (per Lux 7aac5aa):

1. Application data export uses supported authenticated paths only
   (Path A1/A2/A3); no `COPY TO /tmp`
2. Application data import uses `psql \copy` with FK-respecting order
3. Auth migration DEFAULT is re-onboarding/password-reset; raw CSV
   import is NOT canonical
4. Auth user-id mapping has explicit Option B (legacy_user_id audit
   column) recommended
5. PRIME does not auto-create the legacy_user_id migration in this
   round; it should be a separate additive migration in the next round

After Lux accept: Founder can begin Wave 1 (schema apply) through
authenticated Dashboard SQL Editor or `supabase login` + `supabase link`.
