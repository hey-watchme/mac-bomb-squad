# Bomb Squad Implementation Roadmap

This is the resumable execution plan after the app rename. Keep this file
updated whenever a phase starts, finishes, or changes direction.

## Current Checkpoint

- Repository: `git@github.com:hey-watchme/mac-bomb-squad.git`
- Branch: `main`
- Last pushed commit: `5c40db5 Add implementation roadmap`
- App target: `BombSquad`
- Bundle ID: `com.heywatchme.bombsquad`
- Generated project: `BombSquad.xcodeproj`
- Build check:

```bash
xcodebuild -project BombSquad.xcodeproj -scheme BombSquad -configuration Debug build
```

## Guiding Constraints

- Keep one shared identity across macOS, future iOS, Android, and web.
- Do not ship LLM provider keys in client apps.
- Use the existing Supabase project, but prefix app-owned tables with `bs_`.
- Treat Supabase Auth as shared infrastructure; app-specific state belongs in
  prefixed public tables.
- Start with Vercel/Supabase/Stripe. Add AWS only for queue-backed or heavy AI
  jobs that need it.
- Keep enterprise readiness lightweight: tenant IDs, usage events, prompt
  profiles, and routing policies can exist before enterprise features are fully
  built.

## Phase 0: Repository Hygiene

Status: ready

- Confirm `main` is clean before starting each phase.
- Use small commits per phase.
- Run `xcodegen generate` after `project.yml` changes.
- Run the Debug build before each push.
- Keep generated `.xcodeproj` ignored.

## Phase 1: Supabase Schema

Status: in progress

Goal: create app-owned tables that can coexist with older projects in the same
Supabase instance.

Table prefix: `bs_`

Initial tables:

- `bs_profiles`
- `bs_tenants`
- `bs_tenant_members`
- `bs_entitlements`
- `bs_usage_events`
- `bs_app_devices`

Later tables:

- `bs_prompt_profiles`
- `bs_ai_routing_policies`
- `bs_audit_events`

Implementation files:

- `supabase/migrations/0001_bs_core_schema.sql`
- `docs/supabase-setup.md`

Acceptance:

- Migration can be reviewed before applying.
- RLS policies are included.
- New user bootstrap path creates a personal tenant, membership, profile, and
  free entitlement with `monthly_review_limit = 50`.
- Existing non-Bomb Squad tables are untouched.

## Phase 2: Auth Configuration

Status: pending Phase 1

Goal: make account login work before paid plans.

Providers:

- Google OAuth
- Apple ID
- Email OTP

Implementation files:

- `BombSquad/Services/AuthClient.swift`
- `BombSquad/ViewModels/AuthViewModel.swift`
- `BombSquad/Views/AuthView.swift`
- `BombSquad/Views/SettingsView.swift`
- `project.yml` if entitlements or URL schemes are needed

Acceptance:

- User can sign in and out.
- Session persists across app launches.
- App can retrieve a Supabase access token for API calls.
- Settings or account panel shows signed-in email and current tenant.

## Phase 3: AI Gateway MVP

Status: pending Phase 2

Goal: move provider keys out of the macOS app.

Recommended package layout:

- `web/` for a Next.js app on Vercel
- `web/app/api/ai/review/route.ts`
- `web/lib/supabaseAdmin.ts`
- `web/lib/entitlements.ts`
- `web/lib/usage.ts`
- `web/lib/providers/openai-compatible.ts`
- `web/lib/providers/anthropic.ts`

Request flow:

- Verify Supabase JWT.
- Resolve tenant.
- Check entitlement and monthly quota.
- Call configured LLM provider.
- Insert `bs_usage_events`.
- Return the existing `ReviewResult` shape.

Acceptance:

- Free users are limited to 50 successful review/transform operations per month.
- Over-quota responses are structured and user-readable.
- macOS app no longer requires OpenAI/Groq/Claude keys for normal usage.

## Phase 4: macOS API Client Cutover

Status: pending Phase 3

Goal: replace direct provider calls with product API calls while keeping the old
provider clients available only as temporary development fallback if needed.

Implementation files:

- `BombSquad/Services/BombSquadAPIClient.swift`
- `BombSquad/Services/ReviewProvider.swift`
- `BombSquad/ViewModels/ReviewViewModel.swift`
- `BombSquad/Views/SettingsView.swift`

Acceptance:

- Review and transform work through `/api/ai/review`.
- Errors distinguish unauthenticated, over quota, payment required, and provider
  failure.
- Settings no longer presents provider API keys as the normal user path.

## Phase 5: Stripe Billing

Status: pending Phase 3

Goal: add paid plans and entitlement sync.

Implementation files:

- `web/app/pricing/page.tsx`
- `web/app/api/billing/checkout/route.ts`
- `web/app/api/billing/portal/route.ts`
- `web/app/api/stripe/webhook/route.ts`
- `web/lib/stripe.ts`

Acceptance:

- User can open Stripe Checkout from the web or app.
- User can manage billing in Stripe Customer Portal.
- Stripe webhook updates `bs_entitlements`.
- App reflects free/pro status and remaining quota.

## Phase 6: Admin and Operations

Status: pending Phase 5

Goal: make early support possible without building a large admin system.

Implementation files:

- `web/app/admin/page.tsx`
- `web/app/admin/users/page.tsx`
- `web/app/admin/tenants/page.tsx`
- `web/app/admin/usage/page.tsx`

Acceptance:

- Admin can search users and tenants.
- Admin can inspect subscription status and usage.
- Admin can manually suspend a tenant or grant temporary quota.

## Phase 7: Enterprise and Advanced AI

Status: future

Goal: add enterprise-specific controls only when real requirements appear.

Possible work:

- `bs_prompt_profiles` for tenant and user prompt customization.
- `bs_ai_routing_policies` for per-tenant provider/model/region choices.
- Content retention policies.
- SSO/SAML.
- Queue-backed jobs for audio analysis and long-running processing.
- AWS SQS + ECS/EC2 worker path for heavy audio models.

## First Five Tasks

1. Completed: define the gateway contract and environment variable names in
   `docs/api-contract.md`.
2. Next: write `supabase/migrations/0001_bs_core_schema.sql`.
3. Write `docs/supabase-setup.md` with required project URL, anon key, service
   role key, redirect URLs, and provider configuration steps.
4. Add a small Supabase config layer in macOS using environment or local config
   placeholders without committing secrets.
5. Build the first `AuthClient` and a minimal account/settings UI for email OTP.

Next task after those:

- Scaffold `web/` with the `/api/ai/review` route shape, but keep provider
   execution stubbed until auth is verified end-to-end.

## Contract Notes

Create `docs/api-contract.md` before implementation. It should define:

- API base URL setting names for macOS and web.
- Supabase env vars: project URL, anon key, service role key.
- AI gateway env vars: provider keys, default model, quota limits.
- Stripe env vars: secret key, webhook secret, price IDs.
- Request and response JSON for `/api/ai/review`.
- Standard error codes for unauthenticated, over quota, payment required, and
  provider failure.

## Stop/Resume Rule

At the end of each work session:

- Run `git status -sb`.
- Record the current phase and next task in this file.
- Commit only buildable or reviewable checkpoints.
- Push before switching machines or handing off.
