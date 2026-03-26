# API HTTP Test usage

## Install flow
Run bootstrap once per project:

`HTTP_PROJECT_ROOT=/path/to/repo /path/to/api-http-test/scripts/api_http_test.sh install`

The expected skill UX is `/api-http-test install`, which should invoke the command above.

## Run requests
- GET:
  - `HTTP_PROJECT_ROOT=/path/to/repo HTTP_PROFILE=local /path/to/api-http-test/scripts/api_http_test.sh request GET /health`
- POST JSON:
  - `HTTP_PROJECT_ROOT=/path/to/repo HTTP_PROFILE=local /path/to/api-http-test/scripts/api_http_test.sh request POST /users --body '{"name":"Mario"}'`
- Add query and headers:
  - `... api_http_test.sh request GET /users --query 'page=1&limit=20' --header 'X-Trace-Id: abc-123'`
- Read body from file:
  - `... api_http_test.sh request PUT /users/42 --body-file ./payload.json`

## Use docs/OpenAPI as source of truth
- If `<project-root>/docs/` exists with YAML OpenAPI fragments, resolve requests from docs first:
  - method (`get`/`post`/...)
  - full path (including base prefix like `/api/v2`)
  - required path/query parameters
- Recommended flow before request:
  - locate endpoint in docs YAML
  - copy exact method+path
  - pass required query/path params with `--query` or path substitutions
- Example:
  - docs says `GET /api/v2/users/{id}` -> run `... request GET /api/v2/users/1`

## Notes
- `--path` can be absolute URL or relative to `http.base_url`.
- `HTTP_PROFILE` defaults to `local`.
- `--show-headers` prints response headers.
- For bearer login flow, configure `auth_login_url`, user/password fields, and credentials.
- Cookie session is automatic by default:
  - `Set-Cookie` is persisted to `.skills/api-http-test/.cookies/<profile>.cookies.json`
  - Next requests automatically send `Cookie` header from that jar (unless overridden manually)

## Common troubleshooting
- Missing config:
  - Run install/bootstrap first.
- 401/403:
  - Verify `auth_mode` and credential fields in `.skills/api-http-test/http.toml`.
- Timeout:
  - Increase `timeout_ms` in TOML or pass `--timeout-ms`.
