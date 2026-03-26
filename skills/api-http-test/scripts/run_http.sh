#!/usr/bin/env bash
set -euo pipefail

python3 - "$@" <<'PY'
import argparse
import base64
import json
import os
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def merge_dict(base: dict, override: dict) -> dict:
    out = dict(base)
    out.update(override)
    return out


def build_url(base_url: str, path: str, query: str | None) -> str:
    if path.startswith("http://") or path.startswith("https://"):
        url = path
    else:
        url = base_url.rstrip("/") + "/" + path.lstrip("/")
    if query:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}{query}"
    return url


def parse_headers(header_lines: list[str]) -> dict[str, str]:
    headers = {}
    for line in header_lines:
        if ":" not in line:
            raise ValueError(f"Invalid header '{line}', expected 'Name: Value'")
        name, value = line.split(":", 1)
        headers[name.strip()] = value.strip()
    return headers


def parse_set_cookie_values(set_cookie_headers: list[str]) -> dict[str, str]:
    jar: dict[str, str] = {}
    for raw in set_cookie_headers:
        first = raw.split(";", 1)[0].strip()
        if "=" not in first:
            continue
        name, value = first.split("=", 1)
        name = name.strip()
        value = value.strip()
        if name:
            jar[name] = value
    return jar


def load_cookie_jar(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    out: dict[str, str] = {}
    for k, v in data.items():
        if isinstance(k, str) and isinstance(v, str):
            out[k] = v
    return out


def save_cookie_jar(path: Path, jar: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(jar, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")


def call_http(url: str, method: str, headers: dict[str, str], body: bytes | None, timeout_s: float):
    req = urllib.request.Request(url=url, data=body, method=method.upper())
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            set_cookies = resp.headers.get_all("Set-Cookie") or []
            return resp.getcode(), dict(resp.headers.items()), set_cookies, resp.read()
    except urllib.error.HTTPError as exc:
        set_cookies = exc.headers.get_all("Set-Cookie") if exc.headers else []
        return exc.code, dict(exc.headers.items()) if exc.headers else {}, set_cookies or [], exc.read()


def get_token_from_login(base_url: str, profile: dict, timeout_s: float) -> str:
    login_url = profile.get("auth_login_url")
    username = profile.get("auth_username")
    password = profile.get("auth_password")
    if not login_url or not username or not password:
        raise RuntimeError("Missing login flow fields: auth_login_url/auth_username/auth_password")

    method = str(profile.get("auth_login_method", "POST")).upper()
    user_field = str(profile.get("auth_login_user_field", "username"))
    pass_field = str(profile.get("auth_login_pass_field", "password"))
    token_json_path = str(profile.get("auth_token_json_path", "token"))

    payload = json.dumps({user_field: username, pass_field: password}).encode("utf-8")
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    url = build_url(base_url, login_url, None)
    status, _, _, raw_body = call_http(url, method, headers, payload, timeout_s)
    if status >= 400:
        raise RuntimeError(f"Login flow failed with status {status}")
    data = json.loads(raw_body.decode("utf-8") or "{}")
    current = data
    for key in token_json_path.split("."):
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            raise RuntimeError(f"Token path '{token_json_path}' not found in login response")
    token = str(current).strip()
    if not token:
        raise RuntimeError("Empty token extracted from login response")
    return token


parser = argparse.ArgumentParser(description="Run real HTTP request using api-http-test TOML profile")
parser.add_argument("method", help="HTTP method, e.g. GET/POST")
parser.add_argument("path", help="Request path or full URL")
parser.add_argument("--profile", default=os.getenv("HTTP_PROFILE", "local"))
parser.add_argument("--query", help="Raw query string, e.g. page=1&limit=20")
parser.add_argument("--header", action="append", default=[], help="Extra header: 'Name: Value'")
parser.add_argument("--body", help="Raw request body")
parser.add_argument("--body-file", help="Read body from file")
parser.add_argument("--timeout-ms", type=int, help="Override timeout milliseconds")
parser.add_argument("--show-headers", action="store_true")
args = parser.parse_args()

project_root = Path(os.getenv("HTTP_PROJECT_ROOT", os.getenv("DB_PROJECT_ROOT", os.getcwd())))
config_file = project_root / ".skills" / "api-http-test" / "http.toml"
if not config_file.exists():
    raise SystemExit(f"Missing config: {config_file}. Run '/api-http-test install' first.")

doc = tomllib.loads(config_file.read_text(encoding="utf-8"))
http_root = doc.get("http", {})
profile_cfg = http_root.get(args.profile)
if not isinstance(profile_cfg, dict):
    available = [k for k, v in http_root.items() if isinstance(v, dict)]
    raise SystemExit(f"Profile '{args.profile}' not found. Available profiles: {', '.join(available) or 'none'}")

base_url = str(http_root.get("base_url", "")).strip()
if not base_url:
    raise SystemExit("Missing http.base_url in config")

timeout_ms = int(args.timeout_ms or http_root.get("timeout_ms", 15000))
timeout_s = timeout_ms / 1000.0
auth_mode = str(profile_cfg.get("auth_mode") or http_root.get("auth_mode", "auto")).lower()
cookie_jar_enabled = bool(profile_cfg.get("cookie_jar_enabled", True))
cookie_jar_name = str(profile_cfg.get("cookie_jar_file", f"{args.profile}.cookies.json"))
cookie_jar_path = project_root / ".skills" / "api-http-test" / ".cookies" / cookie_jar_name

defaults = doc.get("headers", {}).get("default", {})
headers = {str(k): str(v) for k, v in defaults.items()} if isinstance(defaults, dict) else {}
headers = merge_dict(headers, parse_headers(args.header))

if args.body_file:
    body_bytes = Path(args.body_file).read_bytes()
elif args.body is not None:
    body_bytes = args.body.encode("utf-8")
else:
    body_bytes = None

if auth_mode == "auto":
    for candidate in ("bearer", "basic", "api_key", "none"):
        if candidate == "none":
            auth_mode = "none"
            break
        if candidate == "bearer" and (
            profile_cfg.get("auth_token") or profile_cfg.get("auth_login_url")
        ):
            auth_mode = "bearer"
            break
        if candidate == "basic" and profile_cfg.get("auth_username") and profile_cfg.get("auth_password"):
            auth_mode = "basic"
            break
        if candidate == "api_key" and profile_cfg.get("api_key_name") and profile_cfg.get("api_key_value"):
            auth_mode = "api_key"
            break

if auth_mode == "bearer":
    token = str(profile_cfg.get("auth_token", "")).strip()
    if not token:
        token = get_token_from_login(base_url, profile_cfg, timeout_s)
    header_name = str(profile_cfg.get("auth_header_name", "Authorization"))
    scheme = str(profile_cfg.get("auth_scheme", "Bearer")).strip()
    headers[header_name] = f"{scheme} {token}".strip()
elif auth_mode == "basic":
    user = str(profile_cfg.get("auth_username", ""))
    password = str(profile_cfg.get("auth_password", ""))
    raw = f"{user}:{password}".encode("utf-8")
    headers["Authorization"] = "Basic " + base64.b64encode(raw).decode("ascii")
elif auth_mode == "api_key":
    key_name = str(profile_cfg.get("api_key_name", "X-API-Key"))
    key_value = str(profile_cfg.get("api_key_value", ""))
    key_in = str(profile_cfg.get("api_key_in", "header")).lower()
    if key_in == "query":
        extra = urllib.parse.urlencode({key_name: key_value})
        args.query = f"{args.query}&{extra}" if args.query else extra
    else:
        headers[key_name] = key_value
elif auth_mode != "none":
    raise SystemExit(f"Unsupported auth_mode '{auth_mode}'")

jar_cookies: dict[str, str] = {}
if cookie_jar_enabled:
    jar_cookies = load_cookie_jar(cookie_jar_path)
    if "Cookie" not in headers and jar_cookies:
        headers["Cookie"] = "; ".join(f"{k}={v}" for k, v in jar_cookies.items())

url = build_url(base_url, args.path, args.query)
status, response_headers, set_cookie_headers, response_body = call_http(url, args.method, headers, body_bytes, timeout_s)

saved_count = 0
if cookie_jar_enabled and set_cookie_headers:
    new_values = parse_set_cookie_values(set_cookie_headers)
    if new_values:
        jar_cookies.update(new_values)
        save_cookie_jar(cookie_jar_path, jar_cookies)
        saved_count = len(new_values)

print(f"HTTP {status}")
print(f"URL: {url}")
print(f"Auth mode: {auth_mode}")
if cookie_jar_enabled:
    print(f"Cookie jar: {cookie_jar_path}")
    print(f"Cookie updates: {saved_count}")
if args.show_headers:
    print("Response headers:")
    for k, v in sorted(response_headers.items()):
        if k.lower() == "set-cookie":
            print(f"- {k}: <redacted>")
        else:
            print(f"- {k}: {v}")

raw_text = response_body.decode("utf-8", errors="replace")
print("Body:")
try:
    parsed = json.loads(raw_text)
    print(json.dumps(parsed, indent=2, ensure_ascii=True))
except Exception:
    print(raw_text)
PY
