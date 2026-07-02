# Bomb Squad API Contract

This document fixes the first stable contract between Bomb Squad clients and
the server-side product API.

Scope:

- macOS app
- future iOS app
- future Android app
- future web client
- initial Vercel-hosted AI gateway

The purpose of this file is to freeze the names and payload shapes before
implementation starts, so the client and server can move independently without
drift.

## Versioning

- Contract version: `v1`
- Base path: `/api`
- First implemented route: `POST /api/ai/review`

Future routes will reuse the same authentication and envelope conventions:

- `POST /api/ai/transform`
- `POST /api/ai/transcribe`
- `POST /api/ai/analyze-audio`

## Authentication

All product API requests must carry a Supabase access token.

Required header:

```http
Authorization: Bearer <supabase_access_token>
```

Optional header:

```http
X-Bomb-Squad-Request-Id: <uuid-or-client-generated-id>
```

Rules:

- The gateway verifies the Supabase JWT on every request.
- The gateway resolves `user_id` from the token, never from client-supplied
  body data.
- The client may send a request ID in both header and body. If both are
  present, they must match.

## Environment Variables

### macOS App

These names are reserved now, even if the first implementation reads them from
scheme environment variables, a plist, or a local config wrapper.

- `BOMB_SQUAD_API_BASE_URL`
- `BOMB_SQUAD_SUPABASE_URL`
- `BOMB_SQUAD_SUPABASE_ANON_KEY`

Notes:

- No server-side secret goes into the app.
- The app must never contain `SUPABASE_SERVICE_ROLE_KEY`.
- The app must never contain LLM provider API keys in the production path.

### Web / Vercel

Public client vars:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_BOMB_SQUAD_API_BASE_URL`

Server-only vars:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `BOMB_SQUAD_DEFAULT_MODEL_VENDOR`
- `BOMB_SQUAD_DEFAULT_MODEL_ID`
- `BOMB_SQUAD_FREE_MONTHLY_REVIEW_LIMIT`
- `OPENAI_API_KEY`
- `GROQ_API_KEY`
- `ANTHROPIC_API_KEY`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_PRO_MONTHLY`
- `STRIPE_PRICE_TEAM_MONTHLY`
- `STRIPE_PRICE_ENTERPRISE_MONTHLY`

Rules:

- `SUPABASE_URL` should match `NEXT_PUBLIC_SUPABASE_URL`.
- `SUPABASE_ANON_KEY` is available to both product site and client auth flows.
- `SUPABASE_SERVICE_ROLE_KEY` is server-only.
- Provider keys stay server-only.

## API Conventions

### JSON

- Request and response bodies are JSON.
- Keys use `snake_case`.
- Unknown response keys should be ignored by clients.

### Idempotency

- `request_id` is required for all AI operations.
- The gateway uses `tenant_id + request_id` to prevent duplicate usage events.
- Client retries must reuse the same `request_id`.

### Time

- All timestamps are ISO 8601 UTC strings.

## POST /api/ai/review

This is the first route. It covers both current macOS modes:

- outgoing draft review: `mode = compose`
- received-message restructuring: `mode = transform`

### Request Body

```json
{
  "request_id": "8d74bb7a-54aa-4b7b-a947-b68f4a34b5d2",
  "operation": "review",
  "mode": "compose",
  "input": {
    "draft": "今日の会議なんだけど、先方の対応がかなり雑で困っています。"
  },
  "preferences": {
    "output_language": "japanese",
    "model_preference": {
      "vendor": "groq",
      "model_id": "openai/gpt-oss-120b"
    }
  },
  "client": {
    "platform": "macos",
    "app_version": "0.1.0",
    "build_number": "1",
    "device_id": "2f7e7e3b-6bdb-49f6-91f0-8f8f9c7d4f0f"
  }
}
```

### Optional Input Extensions (added 2026-07-02, Universal I/O M3)

`input` accepts two optional objects. Both are reference material for the
prompt; the gateway never persists them.

```json
{
  "input": {
    "draft": "...",
    "context": {
      "app_name": "Slack",
      "window_title": "Threads - Wealth Park",
      "conversation_excerpt": "（周辺会話の抜粋、最大2500文字目安）"
    },
    "memory": {
      "persona_md": "（ユーザーのスタイルプロファイル Markdown）",
      "relationship_subject": "Yumi Mukai",
      "relationship_md": "（相手カード Markdown）"
    }
  }
}
```

- `input.context`: L1 situational context captured at panel summon time.
- `input.memory`: persona/relationship cards. These live client-side until the
  memory sync API ships; clients send the already-selected cards per request.
- The gateway records only boolean flags (`has_context`, `has_memory`) in
  usage metadata, never the content.

### Request Fields

- `request_id`: required string
- `operation`: required string, must be `review` in v1
- `mode`: required string, `compose` or `transform`
- `input.draft`: required string
- `preferences.output_language`: required string, `japanese` or `english`
- `preferences.model_preference.vendor`: optional string
- `preferences.model_preference.model_id`: optional string
- `client.platform`: required string, `macos`, `ios`, `android`, or `web`
- `client.app_version`: required string
- `client.build_number`: optional string
- `client.device_id`: optional string

Rules:

- If `mode = transform`, the route is still `/api/ai/review` in v1.
- `model_preference` is advisory. The gateway may ignore it based on plan,
  policy, or availability.
- Empty or whitespace-only `input.draft` is rejected with `BAD_REQUEST`.

### Success Response

```json
{
  "request_id": "8d74bb7a-54aa-4b7b-a947-b68f4a34b5d2",
  "result": {
    "issues": [
      {
        "category": "impoliteness",
        "severity": "medium",
        "excerpt": "かなり雑",
        "explanation": "相手への評価が直接的で、受け手に防御反応を起こしやすい表現です。",
        "suggestion": "事実ベースの困りごとに言い換えると伝わりやすくなります。"
      }
    ],
    "revised_text": "今日の会議について、先方対応で確認したい点がいくつかありました。",
    "summary": "表現のトゲを抑えつつ要点を残しました。"
  },
  "meta": {
    "mode": "compose",
    "output_language": "japanese",
    "model_vendor": "groq",
    "model_id": "openai/gpt-oss-120b",
    "latency_ms": 842
  },
  "quota": {
    "plan": "free",
    "used": 12,
    "limit": 50,
    "remaining": 38,
    "resets_at": "2026-07-01T00:00:00Z"
  }
}
```

### Success Response Notes

- `result` matches the existing macOS `ReviewResult` shape.
- `issues[].category` values:
  - `typo`
  - `impoliteness`
  - `unclear`
- `issues[].severity` values:
  - `low`
  - `medium`
  - `high`
- `quota` is returned on success so clients can show remaining allowance
  without a separate request.

## Error Contract

Error responses must follow this shape:

```json
{
  "error": {
    "code": "QUOTA_EXCEEDED",
    "message": "Free plan monthly review limit reached.",
    "details": {
      "plan": "free",
      "used": 50,
      "limit": 50,
      "resets_at": "2026-07-01T00:00:00Z"
    }
  },
  "request_id": "8d74bb7a-54aa-4b7b-a947-b68f4a34b5d2"
}
```

### Standard Error Codes

- `BAD_REQUEST`
  - HTTP 400
  - Invalid body, missing fields, empty draft
- `UNAUTHENTICATED`
  - HTTP 401
  - Missing or invalid Supabase token
- `TENANT_ACCESS_DENIED`
  - HTTP 403
  - User token valid but tenant access invalid
- `PAYMENT_REQUIRED`
  - HTTP 402
  - Plan or entitlement does not allow requested operation/model
- `QUOTA_EXCEEDED`
  - HTTP 429
  - Free or paid usage cap reached
- `PROVIDER_ERROR`
  - HTTP 502
  - Upstream LLM provider failed
- `INTERNAL_ERROR`
  - HTTP 500
  - Unclassified server failure

Client behavior:

- `UNAUTHENTICATED`: prompt sign-in
- `TENANT_ACCESS_DENIED`: show account/tenant error
- `PAYMENT_REQUIRED`: show upgrade/paywall path
- `QUOTA_EXCEEDED`: show remaining-cycle limit message
- `PROVIDER_ERROR`: retryable server-side failure message

## Mapping To Existing macOS Models

Current macOS types already match most of the response contract:

- `ReviewResult`
- `ReviewIssue`
- `IssueCategory`
- `Severity`
- `ReviewMode`
- `OutputLanguage`

Expected client mapping:

- `response.result` -> `ReviewResult`
- `response.meta.latency_ms` -> `ReviewViewModel.lastDurationMs`
- `response.meta.model_vendor + model_id` -> display string
- `response.quota` -> future account/quota UI

## Deferred Routes

These are reserved but not implemented in the first pass.

### POST /api/ai/transcribe

Expected future input:

- audio file or multipart upload
- `request_id`
- `client`

Expected future output:

- transcript text
- duration
- quota usage

### POST /api/ai/analyze-audio

Expected future use:

- emotion analysis
- acoustic event analysis
- long-running or async worker path

## Implementation Rule

Before building the macOS `BombSquadAPIClient` or the Next.js route handler,
both sides should use this document as the source of truth for:

- environment variable names
- request body fields
- response envelope
- error codes
