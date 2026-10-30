#!/usr/bin/env bats
# CLI-level tests for ops-deploy. Docker and curl are replaced by shims.

setup() {
  TEST_ROOT="$(mktemp -d)"
  export OPS_DEPLOY_ROOT="$TEST_ROOT"
  export OPS_DEPLOY_APPS_DIR="$BATS_TEST_DIRNAME/fixtures/apps"
  export OPS_DEPLOY_DYNAMIC_DIR="$TEST_ROOT/dynamic"
  export OPS_DEPLOY_STATE_DIR="$TEST_ROOT/state"
  export OPS_DEPLOY_PROBE_MODE=local
  export OPS_DEPLOY_DRAIN_SECONDS=0
  export OPS_DEPLOY_PUBLIC_RETRIES=1
  export OPS_DEPLOY_PUBLIC_INTERVAL=0
  export OPS_DEPLOY_ACTOR=tester
  export OPS_DEPLOY_COMMIT=deadbeef
  export SHIM_STATE="$TEST_ROOT/state"
  export SHIM_LOG="$TEST_ROOT/shim.log"
  mkdir -p "$SHIM_STATE" "$TEST_ROOT/dynamic"
  export PATH="$BATS_TEST_DIRNAME/shims:$PATH"
  OPS="$BATS_TEST_DIRNAME/../scripts/ops-deploy"
  chmod +x "$BATS_TEST_DIRNAME/shims/"* "$OPS"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

bootstrap() {
  run "$OPS" bootstrap test-app "${1:-1.0.0}"
  [ "$status" -eq 0 ]
}

@test "bootstrap creates the blue slot, records success and writes the route" {
  run "$OPS" bootstrap test-app 1.0.0
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  grep -q '"app":"test-app".*"version":"1.0.0".*"slot":"blue".*"action":"bootstrap".*"result":"success"' "$SHIM_STATE/releases.jsonl"
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q 'Host(`test-app.internal.example.com`)' "$TEST_ROOT/dynamic/test-app.yml"
}

@test "bootstrap is refused when a stable release already exists" {
  bootstrap
  run "$OPS" bootstrap test-app 2.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"já existe release estável"* ]]
}

@test "recover recreates the active slot from the release ledger" {
  bootstrap
  rm -f "$SHIM_STATE/services/app-test-app-blue" "$SHIM_STATE/services/app-test-app-blue.replicas"
  run "$OPS" recover test-app
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.0".*"slot":"blue".*"action":"recover".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "deploy without bootstrap is refused" {
  run "$OPS" deploy test-app 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"nenhuma release estável"* ]]
  [ ! -f "$TEST_ROOT/dynamic/test-app.yml" ]
}

@test "deploy rejects mutable versions such as latest" {
  run "$OPS" bootstrap test-app latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"não é imutável"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]
}

@test "deploy promotes the healthy candidate to the inactive slot" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-green" ]
  grep -q 'app-test-app-green:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.1".*"slot":"green".*"action":"deploy".*"result":"success"' "$SHIM_STATE/releases.jsonl"
  [ "$(cat "$SHIM_STATE/services/app-test-app-blue.replicas")" = "0" ]
}

@test "deploy keeps the active slot running when it is not healthy" {
  bootstrap
  echo blue >"$SHIM_STATE/unhealthy"
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"pré-condição falhou"* ]]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  ! grep -q '"version":"1.0.1".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "deploy rejects a sick candidate without switching traffic" {
  bootstrap
  echo green >"$SHIM_STATE/unhealthy"
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"tráfego mantido"* ]]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.1".*"slot":"green".*"action":"deploy".*"result":"failed"' "$SHIM_STATE/releases.jsonl"
  [ "$(cat "$SHIM_STATE/services/app-test-app-green.replicas")" = "0" ]
}

@test "deploy restores the previous route when the public check fails" {
  bootstrap
  touch "$SHIM_STATE/public-fail"
  run "$OPS" deploy test-app 1.0.2
  [ "$status" -eq 1 ]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  [ "$(cat "$SHIM_STATE/services/app-test-app-green.replicas")" = "0" ]
  grep -q '"version":"1.0.2".*"result":"failed"' "$SHIM_STATE/releases.jsonl"
}

@test "verify prints machine readable health for the active slot" {
  bootstrap
  run "$OPS" verify test-app
  [ "$status" -eq 0 ]
  [[ "$output" == *'"app":"test-app"'* ]]
  [[ "$output" == *'"slot":"blue"'* ]]
  [[ "$output" == *'"healthy":true'* ]]
}

@test "verify fails with exit 1 when the active slot is unhealthy" {
  bootstrap
  echo blue >"$SHIM_STATE/unhealthy"
  run "$OPS" verify test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *'"healthy":false'* ]]
}

@test "verify fails with exit 1 when the health probe times out" {
  bootstrap
  run env SHIM_CURL_FORCE_TIMEOUT=1 "$OPS" verify test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *'"healthy":false'* ]]
  [[ "$output" == *'"http_code":""'* ]]
}

@test "rollback restores the previous stable version and records the event" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]

  run "$OPS" rollback test-app
  [ "$status" -eq 0 ]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.0".*"slot":"blue".*"action":"rollback".*"result":"success"' "$SHIM_STATE/releases.jsonl"
  grep -q '"message":"rollback de 1.0.1 para 1.0.0"' "$SHIM_STATE/releases.jsonl"
  [ "$(cat "$SHIM_STATE/services/app-test-app-green.replicas")" = "0" ]

  run "$OPS" status test-app
  [[ "$output" == *"versão ativa: 1.0.0"* ]]
}

@test "rollback refuses a version that is not in the stable history" {
  bootstrap
  run "$OPS" rollback test-app 9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" == *"não consta como estável"* ]]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
}

@test "rollback failure after switching keeps the restored version for diagnosis" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  touch "$SHIM_STATE/public-fail"

  run "$OPS" rollback test-app
  [ "$status" -eq 1 ]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"action":"rollback".*"result":"failed".*"verificação pública reprovada' "$SHIM_STATE/releases.jsonl"
  [[ "$output" == *"ALERTA CRÍTICO"* ]]
}

@test "status supports json output and a deploy plus rollback produce distinct records" {
  bootstrap
  run "$OPS" deploy test-app 1.1.0
  [ "$status" -eq 0 ]
  run "$OPS" rollback test-app 1.0.0
  [ "$status" -eq 0 ]

  run "$OPS" status test-app --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"active_version":"1.0.0"'* ]]
  [[ "$output" == *'"active_slot":"blue"'* ]]

  [ "$(grep -c '"action":"deploy","result":"success"' "$SHIM_STATE/releases.jsonl")" -eq 1 ]
  [ "$(grep -c '"action":"rollback","result":"success"' "$SHIM_STATE/releases.jsonl")" -eq 1 ]
  grep -q '"commit":"deadbeef".*"checksum":"[0-9a-f]\{64\}"' "$SHIM_STATE/releases.jsonl"
  grep -q '"author":"tester"' "$SHIM_STATE/releases.jsonl"
}

@test "deploy keeps the persistent volume mount and never removes volumes" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  grep -q 'type=volume,source=test-app-data,target=/data' "$SHIM_LOG"
  ! grep -q 'volume rm' "$SHIM_LOG"
}

@test "deploy applies runtime hardening flags" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  grep -q -- '--read-only' "$SHIM_LOG"
  grep -q -- '--cap-drop ALL' "$SHIM_LOG"
  grep -q -- '--limit-memory 256M' "$SHIM_LOG"
  grep -q -- '--limit-cpu 0.50' "$SHIM_LOG"
  grep -q -- '--limit-pids 128' "$SHIM_LOG"
  grep -q -- '--stop-grace-period 30s' "$SHIM_LOG"
  grep -q -- '--log-opt max-size=10m' "$SHIM_LOG"
  grep -q 'type=tmpfs,destination=/tmp,tmpfs-size=16777216' "$SHIM_LOG"
}
