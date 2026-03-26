#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${HTTP_PROJECT_ROOT:-${DB_PROJECT_ROOT:-$PWD}}"
CONFIG_DIR="${PROJECT_ROOT}/.skills/api-http-test"
CONFIG_FILE="${CONFIG_DIR}/http.toml"
PROFILE="${HTTP_PROFILE:-local}"

mkdir -p "$CONFIG_DIR"

infer_mode="auto"
infer_confidence="low"
infer_reason="not evaluated"
if [[ -x "${SCRIPT_DIR}/infer_auth_mode.sh" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      mode) infer_mode="$value" ;;
      confidence) infer_confidence="$value" ;;
      reason) infer_reason="$value" ;;
    esac
  done < <("${SCRIPT_DIR}/infer_auth_mode.sh" "$PROJECT_ROOT")
fi

echo "Project root: ${PROJECT_ROOT}"
echo "Profile: ${PROFILE}"
echo "Auth autodetect: ${infer_mode} (${infer_confidence}) - ${infer_reason}"
echo

read -r -p "Base URL (e.g. https://api.example.com): " base_url
while [[ -z "${base_url}" ]]; do
  read -r -p "Base URL is required, please enter it: " base_url
done

read -r -p "Timeout ms [15000]: " timeout_ms
timeout_ms="${timeout_ms:-15000}"

read -r -p "Auth mode [${infer_mode}] (auto|bearer|basic|api_key|none): " auth_mode
auth_mode="${auth_mode:-$infer_mode}"

profile_auth_mode="$auth_mode"
auth_header_name=""
auth_scheme=""
auth_token=""
auth_login_url=""
auth_login_method=""
auth_login_user_field=""
auth_login_pass_field=""
auth_username=""
auth_password=""
api_key_name=""
api_key_value=""
api_key_in=""

case "$auth_mode" in
  bearer)
    read -r -p "Authorization header name [Authorization]: " auth_header_name
    auth_header_name="${auth_header_name:-Authorization}"
    read -r -p "Auth scheme prefix [Bearer]: " auth_scheme
    auth_scheme="${auth_scheme:-Bearer}"
    read -r -p "Static token (optional, leave blank to use login flow): " auth_token
    if [[ -z "$auth_token" ]]; then
      read -r -p "Login URL path (e.g. /auth/login): " auth_login_url
      read -r -p "Login method [POST]: " auth_login_method
      auth_login_method="${auth_login_method:-POST}"
      read -r -p "Username field [username]: " auth_login_user_field
      auth_login_user_field="${auth_login_user_field:-username}"
      read -r -p "Password field [password]: " auth_login_pass_field
      auth_login_pass_field="${auth_login_pass_field:-password}"
      read -r -p "Username: " auth_username
      read -r -s -p "Password: " auth_password
      echo
    fi
    ;;
  basic)
    read -r -p "Username: " auth_username
    read -r -s -p "Password: " auth_password
    echo
    ;;
  api_key)
    read -r -p "API key location [header] (header|query): " api_key_in
    api_key_in="${api_key_in:-header}"
    read -r -p "API key name [X-API-Key]: " api_key_name
    api_key_name="${api_key_name:-X-API-Key}"
    read -r -s -p "API key value: " api_key_value
    echo
    ;;
  auto|none)
    ;;
  *)
    echo "Unsupported auth_mode '${auth_mode}', using auto."
    profile_auth_mode="auto"
    ;;
esac

export CONFIG_FILE PROFILE base_url timeout_ms auth_mode profile_auth_mode
export auth_header_name auth_scheme auth_token auth_login_url auth_login_method
export auth_login_user_field auth_login_pass_field auth_username auth_password
export api_key_name api_key_value api_key_in

python3 - <<'PY'
import os
from pathlib import Path

def esc(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')

config_file = Path(os.environ["CONFIG_FILE"])
profile = os.environ["PROFILE"]
base_url = os.environ["base_url"]
timeout_ms = os.environ["timeout_ms"]
auth_mode = os.environ["auth_mode"]
profile_auth_mode = os.environ["profile_auth_mode"]

lines = [
    "[configuration]",
    'schema_version = "1.0.0"',
    "",
    "[http]",
    f'base_url = "{esc(base_url)}"',
    f"timeout_ms = {int(timeout_ms)}",
    f'auth_mode = "{esc(auth_mode)}"',
    "",
    f"[http.{profile}]",
    f'description = "{profile} profile"',
    f'auth_mode = "{esc(profile_auth_mode)}"',
]

def add_if(name: str, value: str) -> None:
    if value:
        lines.append(f'{name} = "{esc(value)}"')

add_if("auth_header_name", os.environ.get("auth_header_name", ""))
add_if("auth_scheme", os.environ.get("auth_scheme", ""))
add_if("auth_token", os.environ.get("auth_token", ""))
add_if("auth_login_url", os.environ.get("auth_login_url", ""))
add_if("auth_login_method", os.environ.get("auth_login_method", ""))
add_if("auth_login_user_field", os.environ.get("auth_login_user_field", ""))
add_if("auth_login_pass_field", os.environ.get("auth_login_pass_field", ""))
add_if("auth_username", os.environ.get("auth_username", ""))
add_if("auth_password", os.environ.get("auth_password", ""))
add_if("api_key_name", os.environ.get("api_key_name", ""))
add_if("api_key_value", os.environ.get("api_key_value", ""))
add_if("api_key_in", os.environ.get("api_key_in", ""))

lines.extend([
    "",
    "[headers.default]",
    'Accept = "application/json"',
    'Content-Type = "application/json"',
    "",
])

config_file.write_text("\n".join(lines), encoding="utf-8")
PY

if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git -C "$PROJECT_ROOT" check-ignore -q ".skills/api-http-test/http.toml"; then
    echo "Warning: .skills/api-http-test/http.toml is not gitignored in this repo."
    echo "Add it to .gitignore to avoid committing credentials."
  fi
fi

echo "Created ${CONFIG_FILE}"
echo "Next step: run requests with ${SCRIPT_DIR}/run_http.sh"
