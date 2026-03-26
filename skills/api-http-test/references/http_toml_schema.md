# http.toml schema

Path: `<project-root>/.skills/api-http-test/http.toml`

## Minimal example

```toml
[configuration]
schema_version = "1.0.0"

[http]
base_url = "http://localhost:3000"
timeout_ms = 15000
auth_mode = "auto"

[http.local]
description = "local profile"
auth_mode = "bearer"
cookie_jar_enabled = true
cookie_jar_file = "local.cookies.json"
auth_header_name = "Authorization"
auth_scheme = "Bearer"
auth_login_url = "/auth/login"
auth_login_method = "POST"
auth_login_user_field = "username"
auth_login_pass_field = "password"
auth_username = "demo"
auth_password = "demo"

[headers.default]
Accept = "application/json"
Content-Type = "application/json"
```

## Sections
- `[configuration]`
  - `schema_version` (string): current schema version.
- `[http]`
  - `base_url` (string): API base URL.
  - `timeout_ms` (int): request timeout in milliseconds.
  - `auth_mode` (string): default auth mode (`auto|bearer|basic|api_key|none`).
- `[http.<profile>]`
  - Per-environment overrides and auth credentials.
  - Suggested profiles: `local`, `staging`, `prod`.
  - Cookie session support:
    - `cookie_jar_enabled` (bool, default `true`)
    - `cookie_jar_file` (string, default `<profile>.cookies.json`, stored in `.skills/api-http-test/.cookies/`)
- `[headers.default]`
  - Map of default headers applied to each request.

## Auth fields
- bearer:
  - `auth_header_name`, `auth_scheme`, `auth_token` (optional static token)
  - login flow fields: `auth_login_url`, `auth_login_method`, `auth_login_user_field`, `auth_login_pass_field`, `auth_username`, `auth_password`, `auth_token_json_path` (optional, default `token`)
- basic:
  - `auth_username`, `auth_password`
- api_key:
  - `api_key_name`, `api_key_value`, `api_key_in` (`header|query`)

## Security
- Keep the TOML gitignored.
- Avoid storing production secrets in plain text when possible.
- Cookie jar files may contain session tokens; keep `.skills/api-http-test/.cookies/` gitignored.
