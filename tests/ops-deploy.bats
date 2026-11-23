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
  export TEST_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  export OPS_DEPLOY_IMAGE_DIGEST="$TEST_DIGEST"
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

@test "bootstrap is refused when any route file already exists" {
  printf 'http:\n  routers: {}\n' >"$TEST_ROOT/dynamic/test-app.yml"

  run "$OPS" bootstrap test-app 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"já existe arquivo de rota"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]
  [ ! -f "$SHIM_STATE/releases.jsonl" ]
}

@test "bootstrap records a failure when the initial service cannot be created" {
  run env SHIM_DOCKER_FAIL_CREATE=1 OPS_DEPLOY_RETRY_MAX=1 "$OPS" bootstrap test-app 1.0.0
  [ "$status" -eq 1 ]
  grep -q '"action":"bootstrap".*"result":"failed".*"falha ao criar o serviço inicial"' "$SHIM_STATE/releases.jsonl"
  [ ! -f "$TEST_ROOT/dynamic/test-app.yml" ]
}

@test "bootstrap skips public verification when APP_VERIFY_PUBLIC=0" {
  mkdir -p "$TEST_ROOT/apps/no-public"
  sed -e 's/^APP_NAME=.*/APP_NAME=no-public/' \
    -e 's/^APP_DOMAIN=.*/APP_DOMAIN=no-public.internal.example.com/' \
    -e 's/^APP_VERIFY_PUBLIC=.*/APP_VERIFY_PUBLIC=0/' \
    "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/no-public/app.conf"
  touch "$SHIM_STATE/public-fail"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" bootstrap no-public 1.0.0
  [ "$status" -eq 0 ]
  grep -q '"app":"no-public".*"action":"bootstrap".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "recover recreates the desired slot from the route" {
  bootstrap
  rm -f "$SHIM_STATE/services/app-test-app-blue" "$SHIM_STATE/services/app-test-app-blue.replicas"
  run "$OPS" recover test-app
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.0".*"slot":"blue".*"action":"recover".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "recover inherits the ledger digest when the route matches the release" {
  bootstrap
  rm -f "$SHIM_STATE/services/app-test-app-blue" "$SHIM_STATE/services/app-test-app-blue.replicas"
  sed -i 's/ digest=sha256:[0-9a-f]*/ digest=/' "$TEST_ROOT/dynamic/test-app.yml"
  : >"$SHIM_LOG"

  run "$OPS" recover test-app
  [ "$status" -eq 0 ]
  grep -q "test-app:1.0.0@$TEST_DIGEST" "$SHIM_LOG"
}

@test "recover does not inherit a digest from a divergent ledger release" {
  bootstrap
  rm -f "$SHIM_STATE/services/app-test-app-blue" "$SHIM_STATE/services/app-test-app-blue.replicas"
  sed -i 's/^# ops-deploy route: .*/# ops-deploy route: app=test-app version=2.0.0 slot=blue digest=/' \
    "$TEST_ROOT/dynamic/test-app.yml"
  : >"$SHIM_LOG"

  run "$OPS" recover test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALLOW_MUTABLE_TAG"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]

  run env OPS_DEPLOY_ALLOW_MUTABLE_TAG=1 "$OPS" recover test-app
  [ "$status" -eq 0 ]
  grep -q 'test-app:2.0.0' "$SHIM_LOG"
  ! grep -q "test-app:2.0.0@$TEST_DIGEST" "$SHIM_LOG"
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

@test "bootstrap rejects version strings that are not SemVer" {
  run "$OPS" bootstrap test-app 1.2.3.4
  [ "$status" -eq 1 ]
  [[ "$output" == *"não é imutável"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]
}

@test "bootstrap rejects SemVer build metadata that cannot be a Docker tag" {
  run "$OPS" bootstrap test-app 1.2.3+build.5
  [ "$status" -eq 1 ]
  [[ "$output" == *"não é imutável"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]
}

@test "deploy requires an immutable digest" {
  bootstrap
  run env OPS_DEPLOY_ALLOW_MUTABLE_TAG=0 OPS_DEPLOY_IMAGE_DIGEST= "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"digest obrigatório"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-green" ]
}

@test "deploy rejects a malformed digest" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1 --digest sha256:deadbeef
  [ "$status" -eq 1 ]
  [[ "$output" == *"digest inválido"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-green" ]
}

@test "deploy promotes the healthy candidate to the inactive slot" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-green" ]
  grep -q "test-app:1.0.1@$TEST_DIGEST" "$SHIM_LOG"
  grep -q 'app-test-app-green:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.1".*"slot":"green".*"action":"deploy".*"result":"success".*"digest":"sha256:aaaa' "$SHIM_STATE/releases.jsonl"
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
  echo 1.0.2 >"$SHIM_STATE/public-fail-version"
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

@test "verify requires a value for --slot" {
  bootstrap
  run "$OPS" verify test-app --slot
  [ "$status" -eq 2 ]
  [[ "$output" == *"faltou valor para --slot"* ]]
}

@test "status rejects unknown arguments" {
  bootstrap
  run "$OPS" status test-app --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento inválido para status"* ]]
}

@test "verify fails with exit 1 when the active slot is unhealthy" {
  bootstrap
  echo blue >"$SHIM_STATE/unhealthy"
  run "$OPS" verify test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *'"healthy":false'* ]]
}

@test "verify escapes a non-JSON health body into valid JSON" {
  bootstrap
  printf '{"status":"healthy"}\nquoted "x" \\ slash\tend' >"$SHIM_STATE/weird-health-body"
  run "$OPS" verify test-app
  [ "$status" -eq 0 ]
  json_line="$(printf '%s\n' "$output" | grep '^{' | tail -n 1)"
  printf '%s' "$json_line" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["healthy"] is True; assert d["http_code"] == "200"; assert "quoted" in d["body"] and "slash" in d["body"]'
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

@test "rollback refuses a legacy target without a digest unless explicitly allowed" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  sed -i '/"version":"1.0.0".*"action":"bootstrap"/s/"digest":"[^"]*"/"digest":""/' \
    "$SHIM_STATE/releases.jsonl"

  run "$OPS" rollback test-app 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALLOW_MUTABLE_TAG"* ]]
  grep -q 'app-test-app-green:8080' "$TEST_ROOT/dynamic/test-app.yml"

  run env OPS_DEPLOY_ALLOW_MUTABLE_TAG=1 "$OPS" rollback test-app 1.0.0
  [ "$status" -eq 0 ]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
}

@test "rollback failure after switching keeps the restored version for diagnosis" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  echo 1.0.0 >"$SHIM_STATE/public-fail-version"

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

@test "status lists up to five stable versions with deployment date and health" {
  bootstrap
  for v in 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6; do
    run "$OPS" deploy test-app "$v"
    [ "$status" -eq 0 ]
  done

  run "$OPS" status test-app --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"retention_limit":5'* ]]
  [[ "$output" == *'"version":"1.0.6"'* ]]
  [[ "$output" == *'"deployed_at":'* ]]
  [[ "$output" == *'"healthy":true'* ]]
  [ "$(printf '%s' "$output" | grep -o '"version":"[0-9.]*"' | wc -l)" -eq 5 ]
  [[ "$output" != *'"version":"1.0.0"'* ]]

  run "$OPS" status test-app
  [ "$status" -eq 0 ]
  [[ "$output" == *"versões estáveis disponíveis (até 5)"* ]]
  [[ "$output" == *"saudável=sim"* ]]
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
  grep -q -- '--security-opt no-new-privileges:true' "$SHIM_LOG"
  grep -q -- '--cap-drop ALL' "$SHIM_LOG"
  grep -q -- '--limit-memory 256M' "$SHIM_LOG"
  grep -q -- '--limit-cpu 0.50' "$SHIM_LOG"
  grep -q -- '--limit-pids 128' "$SHIM_LOG"
  grep -q -- '--stop-grace-period 30s' "$SHIM_LOG"
  grep -q -- '--log-opt max-size=10m' "$SHIM_LOG"
  grep -q 'type=tmpfs,destination=/tmp,tmpfs-size=16777216' "$SHIM_LOG"
}

@test "deploy falls back when service create lacks --security-opt" {
  bootstrap
  : >"$SHIM_LOG"
  run env SHIM_DOCKER_NO_SECURITY_OPT=1 "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-new-privileges"* ]]
  ! grep -q -- '--security-opt no-new-privileges:true' "$SHIM_LOG"
  grep -q -- '--cap-drop ALL' "$SHIM_LOG"
}

@test "dry-run bootstrap does not create services, routes or ledger entries" {
  run env OPS_DEPLOY_DRY_RUN=1 OPS_DEPLOY_PROBE_MODE=docker "$OPS" bootstrap test-app 1.0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]
  [ ! -f "$TEST_ROOT/dynamic/test-app.yml" ]
  [ ! -f "$SHIM_STATE/releases.jsonl" ]
}

@test "dry-run deploy previews without changing the route or ledger" {
  bootstrap
  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  ledger_before="$(cat "$SHIM_STATE/releases.jsonl")"

  run env OPS_DEPLOY_DRY_RUN=1 OPS_DEPLOY_PROBE_MODE=docker "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-green" ]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
  [ "$(cat "$SHIM_STATE/releases.jsonl")" = "$ledger_before" ]
}

@test "deploy continues when a failed create actually created the service" {
  bootstrap
  run env SHIM_DOCKER_PARTIAL_CREATE=1 OPS_DEPLOY_RETRY_MAX=2 "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-green" ]
  grep -q 'app-test-app-green:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.1".*"slot":"green".*"action":"deploy".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "app.conf rejects a non-boolean APP_READ_ONLY instead of enabling writes" {
  mkdir -p "$TEST_ROOT/apps/bad-read-only"
  sed 's/^APP_NAME=.*/APP_NAME=bad-read-only/' \
    "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/bad-read-only/app.conf"
  echo 'APP_READ_ONLY=true' >>"$TEST_ROOT/apps/bad-read-only/app.conf"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" status bad-read-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"APP_READ_ONLY deve ser 0 ou 1"* ]]
}

@test "app.conf rejects an invalid APP_PIDS_LIMIT instead of dropping the limit" {
  mkdir -p "$TEST_ROOT/apps/bad-pids"
  sed 's/^APP_NAME=.*/APP_NAME=bad-pids/' \
    "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/bad-pids/app.conf"
  echo 'APP_PIDS_LIMIT=many' >>"$TEST_ROOT/apps/bad-pids/app.conf"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" status bad-pids
  [ "$status" -eq 1 ]
  [[ "$output" == *"APP_PIDS_LIMIT inválido"* ]]
}

@test "app.conf rejects a glob in APP_SECRETS instead of expanding it" {
  mkdir -p "$TEST_ROOT/apps/bad-secrets"
  sed 's/^APP_NAME=.*/APP_NAME=bad-secrets/' \
    "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/bad-secrets/app.conf"
  echo 'APP_SECRETS="*"' >>"$TEST_ROOT/apps/bad-secrets/app.conf"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" bootstrap bad-secrets 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"nome de segredo inválido"* ]]
}

@test "recover validates APP_SECRETS before removing the active service" {
  mkdir -p "$TEST_ROOT/apps/test-app"
  cp "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" "$TEST_ROOT/apps/test-app/app.conf"
  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" bootstrap test-app 1.0.0
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]

  printf 'APP_SECRETS="-broken"\n' >>"$TEST_ROOT/apps/test-app/app.conf"
  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  ledger_before="$(cat "$SHIM_STATE/releases.jsonl")"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" recover test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"nome de segredo inválido"* ]]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
  [ "$(cat "$SHIM_STATE/releases.jsonl")" = "$ledger_before" ]
}

@test "recover rejects unexpected extra arguments" {
  bootstrap
  run "$OPS" recover test-app --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento inválido para recover"* ]]
}

@test "rollback rejects unexpected extra arguments" {
  bootstrap
  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  run "$OPS" rollback test-app 1.0.0 --digest "$TEST_DIGEST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento inválido para rollback"* ]]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
}

@test "APP_KEEP_VERSIONS accepts a decimal value with a leading zero" {
  mkdir -p "$TEST_ROOT/apps/zero-versions"
  sed 's/^APP_NAME=.*/APP_NAME=zero-versions/' \
    "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/zero-versions/app.conf"
  echo 'APP_KEEP_VERSIONS=08' >>"$TEST_ROOT/apps/zero-versions/app.conf"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" status zero-versions --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"retention_limit":8'* ]]
}

@test "dry-run deploy does not sleep for the drain window" {
  command -v timeout >/dev/null 2>&1 || skip "timeout não disponível"
  timeout --version >/dev/null 2>&1 || skip "GNU timeout não disponível"
  bootstrap

  run timeout 3 env OPS_DEPLOY_DRY_RUN=1 OPS_DEPLOY_PROBE_MODE=docker \
    OPS_DEPLOY_DRAIN_SECONDS=30 "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "doctor reports ok for a consistent desired, ledger, runtime and observed state" {
  bootstrap
  run "$OPS" doctor test-app --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"ok"'* ]]
  [[ "$output" == *'"consistent":true'* ]]
  [[ "$output" == *'"runtime":{"status":"present","replicas":"1"}'* ]]
  [[ "$output" == *'"observed":{"status":"ok","version":"1.0.0"}'* ]]
}

@test "doctor reports apply-pending and deploy is blocked while Traefik serves a stale version" {
  bootstrap
  echo 0.9.9 >"$SHIM_STATE/public-version"
  run "$OPS" doctor test-app --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"state":"apply-pending"'* ]]

  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"divergência observada"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-green" ]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
}

@test "deploy requires a version-confirming probe unless explicitly overridden" {
  mkdir -p "$TEST_ROOT/apps/unverified"
  sed -e 's/^APP_NAME=.*/APP_NAME=unverified/' \
    -e 's/^APP_DOMAIN=.*/APP_DOMAIN=unverified.internal.example.com/' \
    -e 's/^APP_PUBLIC_EXPECT_VERSION=.*/APP_PUBLIC_EXPECT_VERSION=0/' \
    "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/unverified/app.conf"

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" bootstrap unverified 1.0.0
  [ "$status" -eq 0 ]

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" deploy unverified 1.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"sem confirmação de versão servida"* ]]
  [ ! -f "$SHIM_STATE/services/app-unverified-green" ]

  run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" OPS_DEPLOY_ALLOW_UNVERIFIED=1 "$OPS" deploy unverified 1.0.1
  [ "$status" -eq 0 ]
  grep -q 'app-unverified-green:8080' "$TEST_ROOT/dynamic/unverified.yml"
}

@test "deploy restores the route when the public version does not match the candidate" {
  bootstrap
  echo 1.0.1 >"$SHIM_STATE/public-stale-for-version"
  echo 0.9.9 >"$SHIM_STATE/public-stale-version"

  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"verificação pública reprovada"* ]]
  grep -q 'app-test-app-blue:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"1.0.1".*"action":"deploy".*"result":"failed"' "$SHIM_STATE/releases.jsonl"
}

@test "ledger repairs an incomplete final record before appending a new one" {
  bootstrap
  printf '{"ts":"broken"' >>"$SHIM_STATE/releases.jsonl"

  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  ! grep -q 'broken' "$SHIM_STATE/releases.jsonl"
  grep -q '"version":"1.0.1".*"action":"deploy".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "failed rollback blocks the next deploy and preserves the serving slot" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  echo 1.0.0 >"$SHIM_STATE/public-fail-version"

  run "$OPS" rollback test-app
  [ "$status" -eq 1 ]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]

  run "$OPS" doctor test-app --json
  [ "$status" -eq 2 ]
  [[ "$output" == *'"state":"ledger-drift"'* ]]

  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  : >"$SHIM_LOG"
  run "$OPS" deploy test-app 2.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"divergência"* ]]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
  ! grep -q 'test-app:2.0.0' "$SHIM_LOG"
}

@test "reconcile --accept-route unblocks deploys after a failed rollback" {
  bootstrap
  run "$OPS" deploy test-app 1.0.1
  [ "$status" -eq 0 ]
  echo 1.0.0 >"$SHIM_STATE/public-fail-version"
  run "$OPS" rollback test-app
  [ "$status" -eq 1 ]

  run "$OPS" reconcile test-app --accept-route
  [ "$status" -eq 0 ]
  grep -q '"version":"1.0.0".*"slot":"blue".*"action":"reconcile".*"result":"success"' "$SHIM_STATE/releases.jsonl"

  rm -f "$SHIM_STATE/public-fail-version"
  run "$OPS" deploy test-app 2.0.0
  [ "$status" -eq 0 ]
  grep -q 'app-test-app-green:8080' "$TEST_ROOT/dynamic/test-app.yml"
  grep -q '"version":"2.0.0".*"slot":"green".*"action":"deploy".*"result":"success"' "$SHIM_STATE/releases.jsonl"
}

@test "reconcile rejects conflicting accept flags" {
  bootstrap
  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  ledger_before="$(cat "$SHIM_STATE/releases.jsonl")"

  run "$OPS" reconcile test-app --accept-route --accept-ledger
  [ "$status" -eq 2 ]
  [[ "$output" == *"use apenas um"* ]]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
  [ "$(cat "$SHIM_STATE/releases.jsonl")" = "$ledger_before" ]
}

@test "recover rejects invalid resource settings before touching the active service" {
  for setting in APP_LOG_MAX_SIZE=lots APP_MEMORY_LIMIT=abc APP_CPU_LIMIT=fast APP_STOP_GRACE_PERIOD=soon; do
    field="${setting%%=*}"
    app="bad-$(printf '%s' "$field" | tr '[:upper:]_' '[:lower:]-')"
    mkdir -p "$TEST_ROOT/apps/$app"
    sed -e "s/^APP_NAME=.*/APP_NAME=$app/" \
      -e "s/^APP_DOMAIN=.*/APP_DOMAIN=$app.internal.example.com/" \
      "$BATS_TEST_DIRNAME/fixtures/apps/test-app/app.conf" >"$TEST_ROOT/apps/$app/app.conf"

    run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" bootstrap "$app" 1.0.0
    [ "$status" -eq 0 ]
    echo "$setting" >>"$TEST_ROOT/apps/$app/app.conf"
    route_before="$(cat "$TEST_ROOT/dynamic/$app.yml")"
    ledger_before="$(cat "$SHIM_STATE/releases.jsonl")"

    run env OPS_DEPLOY_APPS_DIR="$TEST_ROOT/apps" "$OPS" recover "$app"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$field"* ]]
    [ -f "$SHIM_STATE/services/app-$app-blue" ]
    [ "$(cat "$TEST_ROOT/dynamic/$app.yml")" = "$route_before" ]
    [ "$(cat "$SHIM_STATE/releases.jsonl")" = "$ledger_before" ]
  done
}


@test "recover requires --from-ledger when the route is missing" {
  bootstrap
  rm -f "$TEST_ROOT/dynamic/test-app.yml" "$SHIM_STATE/services/app-test-app-blue" "$SHIM_STATE/services/app-test-app-blue.replicas"

  run "$OPS" recover test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"--from-ledger"* ]]
  [ ! -f "$SHIM_STATE/services/app-test-app-blue" ]

  run "$OPS" recover test-app --from-ledger
  [ "$status" -eq 0 ]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  [ -f "$TEST_ROOT/dynamic/test-app.yml" ]
}

@test "doctor detects route and ledger digest divergence" {
  bootstrap
  digest="sha256:$(printf 'b%.0s' {1..64})"
  sed -i "s/digest=sha256:[0-9a-f]*/digest=$digest/" "$TEST_ROOT/dynamic/test-app.yml"

  run "$OPS" doctor test-app --json
  [ "$status" -eq 2 ]
  [[ "$output" == *'"state":"ledger-drift"'* ]]
  [[ "$output" == *'"consistent":false'* ]]
  [[ "$output" == *'"ledger":{"version":"1.0.0","slot":"blue","digest":"'"$TEST_DIGEST"'"'* ]]

  run "$OPS" status test-app --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"consistent":false'* ]]
}

@test "recover validates Docker network and secrets before removing the service" {
  bootstrap
  route_before="$(cat "$TEST_ROOT/dynamic/test-app.yml")"
  ledger_before="$(cat "$SHIM_STATE/releases.jsonl")"

  run env SHIM_DOCKER_MISSING_NETWORK=public "$OPS" recover test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"rede Docker"* ]]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]

  run env SHIM_DOCKER_MISSING_SECRETS=test_app_token "$OPS" recover test-app
  [ "$status" -eq 1 ]
  [[ "$output" == *"segredo Docker"* ]]
  [ -f "$SHIM_STATE/services/app-test-app-blue" ]
  [ "$(cat "$TEST_ROOT/dynamic/test-app.yml")" = "$route_before" ]
  [ "$(cat "$SHIM_STATE/releases.jsonl")" = "$ledger_before" ]
}
