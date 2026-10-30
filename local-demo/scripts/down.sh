#!/usr/bin/env bash
# Removes the demo stack. State, registry data and volumes are preserved.
set -Eeuo pipefail
export MSYS_NO_PATHCONV=1

STACK="${DEMO_STACK:-demo-platform}"
docker stack rm "$STACK"
printf 'stack %s removida (volumes, segredos e estado preservados)\n' "$STACK"
