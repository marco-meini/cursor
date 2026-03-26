---
name: api-http-test
description: Run realistic HTTP API tests against real endpoints with project-scoped TOML profiles and auth credentials. Use when the user wants to simulate real API calls, validate auth flows, debug status codes/payloads, or initialize API test config with `/api-http-test install`.
---

# API HTTP Test

## Goal
Use this skill to run real HTTP requests with reusable project configuration and authentication.

## Script location
- `<project-root>/.skills/api-http-test/` is config-only and stores `http.toml`.
- Helper scripts live in the installed skill directory under `scripts/`.
- If the current directory is not the target project, set `HTTP_PROJECT_ROOT=/path/to/repo`.

## First-time setup (required)
- Trigger setup with `/api-http-test install`.
- The install action must call:
  - `HTTP_PROJECT_ROOT=/path/to/repo /path/to/api-http-test/scripts/api_http_test.sh install`
- This creates `.skills/api-http-test/http.toml` in the target project.

## Fast path
- Install/bootstrap profile:
  - `HTTP_PROJECT_ROOT=/path/to/repo /path/to/api-http-test/scripts/api_http_test.sh install`
- Run request:
  - `HTTP_PROJECT_ROOT=/path/to/repo HTTP_PROFILE=local /path/to/api-http-test/scripts/api_http_test.sh request GET /health`
- Run POST with JSON:
  - `HTTP_PROJECT_ROOT=/path/to/repo HTTP_PROFILE=local /path/to/api-http-test/scripts/api_http_test.sh request POST /auth/login --body '{"username":"demo","password":"demo"}'`

## Workflow
1) Ensure project config exists:
   - If `.skills/api-http-test/http.toml` is missing, run bootstrap (`install` flow).
2) Resolve auth mode:
   - Prefer autodetect suggestion during bootstrap.
   - If unclear, use explicit `auth_mode` in TOML (`bearer|basic|api_key|none`).
3) Execute request:
   - Use `run_http.sh` with profile selection (`HTTP_PROFILE` or `--profile`).
   - Support custom headers, query params, and raw/body-file payload.
   - Persist session cookies from `Set-Cookie` and reuse them automatically on next requests.
4) Report outcome:
   - Return status, URL, auth mode used, and response body.

## Trigger rules (summary)
- If user explicitly asks to initialize config or says install, run bootstrap flow.
- If user asks to run/test an endpoint realistically, use `run_http.sh`.
- If auth errors occur (401/403), verify profile auth fields and re-run.
- If no profile is specified and multiple are present, ask user which profile to use.

## Security guardrails
- Do not commit credentials; ensure `.skills/api-http-test/http.toml` is gitignored.
- Do not commit cookie jars; ensure `.skills/api-http-test/.cookies/` is gitignored.
- Mask secrets in explanations when reporting logs.
- Use project-scoped config only for the target repository.

## References
- Usage and examples: `references/http_usage.md`
- TOML schema: `references/http_toml_schema.md`
