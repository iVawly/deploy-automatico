#!/usr/bin/env bash
# Runs the full demo scenario against the local stack: healthy deploy, rejected
# deploy and rollback. Safe to run more than once.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPS="$DEMO_ROOT/scripts/ops"

section() { printf '\n######## %s ########\n' "$*"; }

section "estado atual"
bash "$OPS" status demo-app
bash "$OPS" verify demo-app

section "deploy saudável 1.0.1"
bash "$OPS" deploy demo-app 1.0.1
bash "$OPS" status demo-app
bash "$OPS" verify demo-app

section "deploy reprovado 2.0.0 (dependência quebrada)"
set +e
bash "$OPS" deploy demo-app 2.0.0
rc=$?
set -e
printf '\nexit code do deploy reprovado: %s (esperado: 1)\n' "$rc"
bash "$OPS" status demo-app
bash "$OPS" verify demo-app

section "rollback para 1.0.0"
bash "$OPS" rollback demo-app
bash "$OPS" status demo-app
bash "$OPS" verify demo-app

section "auditoria"
cat "$DEMO_ROOT/state/releases.jsonl"

cat <<'EOF'

Abra https://grafana.127.0.0.1.nip.io/ e consulte:
  {app="demo-app"} | json
  {app="demo-app"} | json | level="error"
EOF
