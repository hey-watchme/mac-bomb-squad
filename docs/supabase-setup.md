# Supabase Setup Notes

This document covers the Bomb Squad-specific setup inside the existing shared
Supabase project.

Project URL:

- `https://qvtlwotzuzbavrzqhyvt.supabase.co`

Database naming rule:

- Bomb Squad-owned tables use the `bs_` prefix.
- Existing tables from other projects are left untouched.

## Current Migration Files

- `supabase/migrations/0001_bs_core_schema.sql`

That migration creates:

- `bs_tenants`
- `bs_profiles`
- `bs_tenant_members`
- `bs_entitlements`
- `bs_usage_events`
- `bs_app_devices`

It also:

- enables RLS
- adds membership helper functions
- adds a Bomb Squad-specific user bootstrap RPC
- backfills existing `auth.users` rows that do not yet have `bs_` records

## Secrets Needed Later

These values should be prepared before client or gateway implementation starts.

### For macOS

- `BOMB_SQUAD_SUPABASE_URL`
- `BOMB_SQUAD_SUPABASE_ANON_KEY`
- `BOMB_SQUAD_API_BASE_URL`

Current runtime resolution order:

1. Xcode Scheme environment variables
2. `Info.plist` keys with the same names

That behavior is implemented in
[BombSquadConfig.swift](/Users/kaya.matsumoto/projects/just-a-moment/BombSquad/Services/BombSquadConfig.swift:1).

### For Vercel / web

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_BOMB_SQUAD_API_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

### For billing and AI gateway

- `OPENAI_API_KEY`
- `GROQ_API_KEY`
- `ANTHROPIC_API_KEY`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_PRO_MONTHLY`
- `STRIPE_PRICE_TEAM_MONTHLY`
- `STRIPE_PRICE_ENTERPRISE_MONTHLY`

The canonical names are defined in [api-contract.md](/Users/kaya.matsumoto/projects/just-a-moment/docs/api-contract.md:1).

## Auth Providers

Planned providers:

- Google OAuth
- Apple ID
- Email OTP

Current decision:

- Supabase Auth is the shared identity layer across macOS, future iOS,
  Android, and web.
- App-specific user/account state lives in `bs_` tables, not in custom auth
  tables.
- Because this Supabase project is shared, Bomb Squad does **not** attach a
  global trigger to `auth.users`. Instead, the client or backend calls
  `public.bs_initialize_current_user()` after a successful Bomb Squad sign-in.

## Redirects And Deep Links

These are not locked yet and must be finalized in the auth implementation
phase.

Expected categories:

- local web auth callback for the product site
- macOS app callback / deep link
- future iOS app callback
- future Android app callback

Do not finalize Google or Apple provider configuration until those callback
values are fixed.

## Applying The Migration

Two safe paths:

1. Review the SQL file in advance, then paste it into the Supabase SQL editor.
2. Apply it through Supabase CLI once local Supabase project wiring is added.

Because this Supabase project is shared with older work, review points before
running:

- confirm every new object is `bs_` prefixed
- confirm there is no global `auth.users` trigger for Bomb Squad bootstrap
- confirm the backfill only touches auth users missing `bs_profiles`
- confirm no existing project tables are altered or dropped

## Expected Result After Apply

For each existing auth user:

- one personal tenant in `bs_tenants`
- one row in `bs_profiles`
- one owner membership in `bs_tenant_members`
- one free entitlement in `bs_entitlements`

For each new Bomb Squad auth user after migration:

- the app or backend calls `select public.bs_initialize_current_user();`
- that call creates the same tenant/profile/membership/entitlement set if absent

Default free plan values:

- `plan = free`
- `status = active`
- `monthly_review_limit = 50`

## Manual Verification Queries

After applying the migration, run checks like these:

```sql
select count(*) from public.bs_profiles;
select count(*) from public.bs_tenants;
select count(*) from public.bs_tenant_members;
select count(*) from public.bs_entitlements;
```

```sql
select p.id, p.email, p.default_tenant_id, e.plan, e.monthly_review_limit
from public.bs_profiles p
join public.bs_entitlements e
  on e.tenant_id = p.default_tenant_id
order by p.created_at desc
limit 20;
```

```sql
select tablename
from pg_tables
where schemaname = 'public'
  and tablename like 'bs_%'
order by tablename;
```

## Next Work After Setup

- Add the first macOS auth client on top of the config layer.
- Add the first auth client for email OTP.
- Scaffold the web AI gateway.
