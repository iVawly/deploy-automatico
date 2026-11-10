#!/usr/bin/env bash
# Runs a pipeline command and appends its stdout/stderr as JSONL to the
# centralized pipeline log collected by Alloy.
# Usage: log-exec.sh <etapa> -- <comando> [args...]
set -Eeuo pipefail

LOG_DIR="${OPS_DEPLOY_LOG_DIR:-/var/log/ops-deploy}"
LOG_FILE="$LOG_DIR/pipeline.jsonl"

usage() {
  printf 'uso: %s <etapa> -- <comando> [args...]\n' "$(basename "$0")" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
stage="$1"
shift
[[ "${1:-}" == "--" ]] && shift
[[ $# -ge 1 ]] || usage

mkdir -p "$LOG_DIR" || {
  printf 'ERROR: não foi possível criar %s\n' "$LOG_DIR" >&2
  exit 1
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
}

redact() {
  local line="$1" name value
  for name in GITHUB_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN OPS_DEPLOY_ALERT_WEBHOOK; do
    value="${!name:-}"
    [[ -n "$value" ]] && line="${line//"$value"/***}"
  done
  printf '%s' "$line"
}

emit() {
  local message="$1"
  printf '{"ts":"%s","source":"pipeline","app":"pipeline","stage":"%s","run_id":"%s","repository":"%s","commit":"%s","actor":"%s","message":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(json_escape "$stage")" \
    "$(json_escape "${GITHUB_RUN_ID:-manual}")" \
    "$(json_escape "${GITHUB_REPOSITORY:-local}")" \
    "$(json_escape "${GITHUB_SHA:-unknown}")" \
    "$(json_escape "${GITHUB_ACTOR:-unknown}")" \
    "$(json_escape "$message")" \
    >>"$LOG_FILE"
}

emit "etapa $stage iniciada"

set +e
"$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(redact "$line")"
  emit "$line"
  printf '%s\n' "$line"
done
status=${PIPESTATUS[0]}
set -e

emit "etapa $stage finalizada com código $status"
exit "$status"
