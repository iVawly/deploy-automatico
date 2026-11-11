#!/usr/bin/env bats
# Validation tests for restore-config.sh. The script needs root for a real
# restore; these tests use its simulation path and skip when root is unavailable.

setup() {
  TEST_ROOT="$(mktemp -d)"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/server/restore-config.sh"
  ARCHIVE="$TEST_ROOT/backup.tar.gz"
  mkdir -p "$TEST_ROOT/src/dynamic"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_restore() {
  if [[ $EUID -eq 0 ]]; then
    run env DEST="$TEST_ROOT/dest" STATE_DIR="$TEST_ROOT/state" bash "$SCRIPT" "$ARCHIVE"
  else
    sudo -n true >/dev/null 2>&1 || skip "requer root ou sudo sem senha"
    run sudo -n env DEST="$TEST_ROOT/dest" STATE_DIR="$TEST_ROOT/state" bash "$SCRIPT" "$ARCHIVE"
  fi
}

@test "restore accepts a regular configuration archive" {
  printf 'http:\n' >"$TEST_ROOT/src/dynamic/platform.yml"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" dynamic

  run_restore
  [ "$status" -eq 0 ]
  [[ "$output" == *"Simulação"* ]]
}

@test "restore rejects symlink entries before extracting" {
  ln -s /etc "$TEST_ROOT/src/dynamic-link"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" dynamic-link

  run_restore
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink"* ]]
  [ ! -e "$TEST_ROOT/dest/dynamic-link" ]
}

@test "restore rejects hardlink entries before extracting" {
  printf 'x\n' >"$TEST_ROOT/src/source"
  ln "$TEST_ROOT/src/source" "$TEST_ROOT/src/hardlink"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" source hardlink

  run_restore
  [ "$status" -eq 1 ]
  [[ "$output" == *"hardlink"* ]]
  [ ! -e "$TEST_ROOT/dest/hardlink" ]
}
