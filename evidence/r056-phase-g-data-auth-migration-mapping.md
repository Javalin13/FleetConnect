# r056 Phase G — Data + Auth Migration Mapping

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Lux 2195825 acceptance)
**Source project:** `rreqjjrmvytnwnsidmqi` (legacy, post-cutover read-only)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, post-Phase G apply)

---

## Purpose

Per Lux 2195825 §8: PRIME cannot directly export from the legacy project
(no service_role key for it). This document is the **canonical mapping**
that the Founder (or a one-shot script using the Founder-provided
service_role key) follows to export + import data + auth users from
legacy to new.

**Why this is a mapping, not a script:**
- The export is a Dashboard-side action (Founder-only via SQL Editor or
  pg_dump). PRIME never holds the legacy service_role key.
- The import is a deterministic, schema-aware operation once the
  migrations are applied on the new project. The mapping below is the
  per-table spec for the import.
- The auth user migration is the highest-risk part (it carries the
  password hashes). It is split into a separate procedure with extra
  safeguards.

---

## 1. Table-by-table data mapping (13 core tables + 5 mailbox)

### 1.1 Core operational tables (13)

| # | Table | Source rows? | Migration path | Notes |
|---|-------|--------------|----------------|-------|
| T1 | `bookings` | Likely thousands (active ops data) | pg_dump CSV → restore via `psql \copy` | PK = `id TEXT` (public booking id). Highest-value, biggest table. |
| T2 | `customers` | Likely hundreds to thousands | pg_dump CSV | PK = `id TEXT` (FC customer code). Linked from T1. |
| T3 | `partners` | Probably 10-100 | pg_dump CSV | PK = `id TEXT` (FC partner code). Includes Ayoub. |
| T4 | `drivers` | Probably 10-100 | pg_dump CSV | PK = `id TEXT` (FC driver code). |
| T5 | `account_requests` | Probably 10-100 (new accounts) | pg_dump CSV | Pre-customer state. |
| T6 | `payments` | Mirrors bookings | pg_dump CSV | Stripe payment intent linkage. |
| T7 | `pricing_profiles` | A few | pg_dump CSV | Rate config; source of truth for km rates. |
| T8 | `fixed_routes` | Probably 10-100 | pg_dump CSV | Pre-priced routes (e.g. Campanile €25). |
| T9 | `invoices` | Hundreds | pg_dump CSV | PDF generation linkage. |
| T10 | `settlements` | Hundreds | pg_dump CSV | Partner payouts. |
| T11 | `ride_reviews` | Probably 100-1000 | pg_dump CSV | 1-5 star reviews from customers. |
| T12 | `refunds` | Tens to hundreds | pg_dump CSV | Stripe refund linkage. |
| T13 | `transaction_ledger` | Thousands (every charge) | pg_dump CSV | Audit-grade financial ledger. Highest integrity. |

### 1.2 Mailbox tables (5 — NOT in legacy per read-only probe)

Per `r056-phase-g-cutover-assessment.md` §2, the 5 mailbox tables are
**404 on legacy** — Phase F was never applied to legacy. **No data to
migrate.** New project starts with an empty mailbox.

| # | Table | Source rows? |
|---|-------|--------------|
| T14 | `dispatch_mailbox_messages` | 0 (legacy never had it) |
| T15 | `dispatch_mailbox_attachments` | 0 |
| T16 | `dispatch_mailbox_audit` | 0 |
| T17 | `dispatch_mailbox_folders` | 0 |
| T18 | `dispatch_mailbox_session_state` | 0 |

### 1.3 Other tables (15 created by migrations, not listed in legacy probe)

These are auxiliary tables created by the migration chain (e.g.
`fixed_route_pricing`, `ride_request_log`, `pricing_tier`). They will
exist on the new project after the 52-migration apply. Their data on
legacy is read-only-untested. If they have rows, they should be migrated;
if empty, no work.

The Founder's export script should include a row count per table so the
decision is data-driven:
```sql
SELECT
  schemaname, relname, n_live_tup
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;
```

---

## 2. Export procedure (Founder, in legacy Supabase Dashboard)

### 2.1 SQL Editor exports (per table)

For each table T1–T13:
1. Open Supabase Dashboard → Project `rreqjjrmvytnwnsidmqi` → SQL Editor.
2. Run:
   ```sql
   COPY (SELECT * FROM public.<table> ORDER BY <pk>) TO '<founder-supplied-presigned-url-or-/tmp-path>' WITH CSV HEADER;
   ```
3. Download the CSV via the response link.

### 2.2 Alternative: pg_dump via Supabase DB connection string

If the Founder has the legacy DB connection string (Dashboard → Settings → Database):
```bash
pg_dump "$LEGACY_DB_URL" \
  --table=public.bookings \
  --table=public.customers \
  --table=public.partners \
  --table=public.drivers \
  --table=public.account_requests \
  --table=public.payments \
  --table=public.pricing_profiles \
  --table=public.fixed_routes \
  --table=public.invoices \
  --table=public.settlements \
  --table=public.ride_reviews \
  --table=public.refunds \
  --table=public.transaction_ledger \
  --data-only --no-owner --column-inserts \
  > fleetconnect-legacy-data-$(date +%Y%m%d).sql
```

This produces a SQL script of `INSERT INTO ... VALUES (...)` statements
that can be replayed on the new project. Column-inserts format is
schema-evolution-safe.

### 2.3 What NOT to export

- `auth.users` — handled by §3 (separate procedure)
- `auth.audit_log_entries` — leave in legacy, new project gets fresh log
- `storage.objects` — none anon-readable per legacy probe, but check
  for private buckets before skipping

---

## 3. Auth users mapping (highest-risk)

### 3.1 What's in `auth.users`

The `auth.users` table holds:
- `id` (UUID, primary key)
- `email` (UNIQUE)
- `encrypted_password` (bcrypt hash; NOT exportable as plaintext)
- `raw_app_meta_data`, `raw_user_meta_data` (JSONB)
- `email_confirmed_at`, `last_sign_in_at`
- `created_at`, `updated_at`

### 3.2 What migration means for passwords

**The bcrypt hash is the bridge.** If the hash is preserved across
projects, the user can log in with their existing password and the new
project will hash-compare against the imported hash.

**Critical caveat:** Supabase's GoTrue layer may use a project-specific
bcrypt salt. Per Supabase docs, the hash format is portable across
projects that share the same JWT secret. **The two projects have
different JWT secrets** (one was created with the legacy project's
secret, the other with the new project's secret). The hash MAY still
work because the salt is per-row, but this is a known risk.

**Founder decision needed (per Lux 2195825 §8.3):**

| Option | Description | Risk | Effort |
|--------|-------------|------|--------|
| A. Hash export + import | `COPY (SELECT id, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at FROM auth.users) ...` and replay on new | Passwords MAY break if salt is project-bound; verified by first login attempt | Low (one SQL script) |
| B. Password reset all users | Send "set new password" email to every user; they re-set on the new project | Zero hash-portability risk; but every user must do an action | Medium (email blast + UI support) |
| C. Hybrid: hash import + reset fallback | Try A; for any user whose first login fails, send reset | Best of both | Medium-high (tracking logic) |

**PRIME recommendation:** Option C. Hash import is fast and usually
works; reset email is the safety net. PRIME does NOT execute either
without explicit Founder authorization.

### 3.3 What about operator/customer/driver linked records?

In `customers`, `partners`, `drivers`, the `user_id` (UUID) column links
the business entity to the `auth.users.id`. **The UUID is the same on
both projects only if the import is deterministic** (i.e. the new
project's `auth.users.id` is the same UUID as the legacy one).

**That works automatically with INSERT-as-SELECT** because we're copying
the literal UUID value. The FKs survive because the UUIDs match.

### 3.4 Auth import SQL (Option A)

```sql
-- Run on new project after migrations applied
-- Founder supplies LEGACY_DB_URL via Dashboard SQL Editor (cross-DB query is NOT supported; this assumes a CSV import path)

-- Step 1: import auth.users from a CSV that the Founder uploaded to a
-- private storage bucket (e.g. 'migration-staging')
COPY auth.users (
  id, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data,
  email_confirmed_at, last_sign_in_at,
  created_at, updated_at
)
FROM '<founder-supplied-storage-signed-url>'
WITH (FORMAT csv, HEADER true);
```

**Same for `auth.identities` (OAuth provider linkage):**
```sql
COPY auth.identities (...) FROM '<...>' WITH (FORMAT csv, HEADER true);
```

**Identity continuity:** users who logged in via Google OAuth (or other
providers) have rows in `auth.identities` keyed by `user_id`. Both must
be migrated together.

---

## 4. Import procedure (Founder, on new project)

### 4.1 Order of operations (deterministic)

The import order respects FK dependencies. Reversing any step fails.

1. **Auth users** (`auth.users`, `auth.identities`) — FIRST. Everyone else
   depends on these UUIDs.
2. **Reference data** (`pricing_profiles`, `fixed_routes`) — small
   tables, no FKs to ops data.
3. **Master data** (`customers`, `partners`, `drivers`) — depends on
   `auth.users.id` for `user_id` FKs.
4. **Operational data** (`bookings`, `payments`, `invoices`, `settlements`,
   `ride_reviews`, `refunds`, `transaction_ledger`, `account_requests`).
5. **Mailbox** — none, see §1.2.

### 4.2 Per-step import command

```bash
# 4.2.1 — Auth users
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY auth.users (...) FROM '/tmp/fc-auth-users.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY auth.identities (...) FROM '/tmp/fc-auth-identities.csv' CSV HEADER"

# 4.2.2 — Reference data
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY pricing_profiles FROM '/tmp/fc-pricing.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY fixed_routes FROM '/tmp/fc-routes.csv' CSV HEADER"

# 4.2.3 — Master data
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY customers FROM '/tmp/fc-customers.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY partners FROM '/tmp/fc-partners.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY drivers FROM '/tmp/fc-drivers.csv' CSV HEADER"

# 4.2.4 — Operational data
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY bookings FROM '/tmp/fc-bookings.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY payments FROM '/tmp/fc-payments.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY invoices FROM '/tmp/fc-invoices.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY settlements FROM '/tmp/fc-settlements.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY ride_reviews FROM '/tmp/fc-reviews.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY refunds FROM '/tmp/fc-refunds.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY transaction_ledger FROM '/tmp/fc-tx.csv' CSV HEADER"
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -c "\\COPY account_requests FROM '/tmp/fc-acct-req.csv' CSV HEADER"
```

### 4.3 Post-import verification

```sql
-- Row count parity (must match legacy within ±0 for every table)
SELECT 'customers' tbl, count(*) FROM customers
UNION ALL SELECT 'partners', count(*) FROM partners
UNION ALL SELECT 'drivers', count(*) FROM drivers
UNION ALL SELECT 'bookings', count(*) FROM bookings
UNION ALL SELECT 'payments', count(*) FROM payments
UNION ALL SELECT 'pricing_profiles', count(*) FROM pricing_profiles
UNION ALL SELECT 'fixed_routes', count(*) FROM fixed_routes
UNION ALL SELECT 'invoices', count(*) FROM invoices
UNION ALL SELECT 'settlements', count(*) FROM settlements
UNION ALL SELECT 'ride_reviews', count(*) FROM ride_reviews
UNION ALL SELECT 'refunds', count(*) FROM refunds
UNION ALL SELECT 'transaction_ledger', count(*) FROM transaction_ledger
UNION ALL SELECT 'account_requests', count(*) FROM account_requests
UNION ALL SELECT 'auth.users', count(*) FROM auth.users
ORDER BY tbl;

-- FK integrity (must be 0 orphans)
SELECT 'orphan customer' issue, count(*) FROM customers c
  WHERE user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = c.user_id);
-- Repeat for partners, drivers, bookings (if bookings has user_id)

-- Idempotency smoke test: try to import one row twice, must fail on PK
```

---

## 5. What this mapping does NOT cover

- **OAuth identity migration for non-GoTrue providers** (if any). Supabase
  GoTrue's `auth.identities` covers Google etc.; if FleetConnect uses a
  custom OAuth, that path is out of scope.
- **Storage objects.** Per legacy probe, storage buckets are empty on
  legacy. If Founder finds non-empty private buckets, that migration is
  a separate S3 copy operation.
- **Edge function runtime state** (e.g. in-flight IMAP IDLE sessions).
  These are not persisted; cutover drops them by design.
- **Realtime channel subscriptions.** Drop on cutover; clients re-subscribe.

---

## 6. Founder-only decisions required

| Decision | Default | Override |
|----------|---------|----------|
| Auth import strategy (A / B / C from §3.2) | A (hash import) | Founder selects C if user complaints expected |
| Pre-import backup of legacy (pg_dump full) | Yes (always) | No (faster cutover) |
| Post-import smoke test (5 random user logins) | Yes (always) | No |
| Pre-cutover reservation/booking freeze window | 15 minutes (no new bookings during cutover) | None (cutover during low-traffic) |

---

## 7. LUX — SYNC NEEDED

- Confirm 13-table data scope (T1–T13)
- Confirm 0-row mailbox scope (T14–T18)
- Confirm import order (§4.1)
- Confirm Option A as default for auth (§3.2)
- Confirm row-count parity + FK integrity checks (§4.3)
- Confirm Founder-only decision list (§6)
