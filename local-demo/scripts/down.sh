#!/usr/bin/env bash
# Removes the demo stack. State, registry data and volumes are preserved.
set -Eeuo pipefail
export MSYS_NO_PATHCONV=1

STACK="${DEMO_STACK:-demo-platform}"
[[ "$STACK" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "DEMO_STACK inválido: $STACK" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker não encontrado" >&2; exit 1; }
docker stack rm "$STACK"
printf 'stack %s removida (volumes, segredos e estado preservados)\n' "$STACK"
