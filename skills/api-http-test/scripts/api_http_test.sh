#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  api_http_test.sh install
  api_http_test.sh request <METHOD> <PATH> [run_http.sh options...]
  api_http_test.sh infer-auth [project-root]

Examples:
  api_http_test.sh install
  HTTP_PROJECT_ROOT=/path/to/repo api_http_test.sh request GET /health
  api_http_test.sh request POST /login --body '{"username":"demo","password":"demo"}'
EOF
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift || true

case "$cmd" in
  install)
    exec "${SCRIPT_DIR}/bootstrap_profile.sh" "$@"
    ;;
  request)
    if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
      echo "request requires METHOD and PATH"
      usage
      exit 1
    fi
    exec "${SCRIPT_DIR}/run_http.sh" "$@"
    ;;
  infer-auth)
    exec "${SCRIPT_DIR}/infer_auth_mode.sh" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
