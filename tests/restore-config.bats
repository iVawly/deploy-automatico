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

run_restore_forced() {
  local backup_dir="$1"
  if [[ $EUID -eq 0 ]]; then
    run env RESTORE_FORCE=1 BACKUP_DIR="$backup_dir" DEST="$TEST_ROOT/dest" \
      STATE_DIR="$TEST_ROOT/state" bash "$SCRIPT" "$ARCHIVE"
  else
    sudo -n true >/dev/null 2>&1 || skip "requer root ou sudo sem senha"
    run sudo -n env RESTORE_FORCE=1 BACKUP_DIR="$backup_dir" DEST="$TEST_ROOT/dest" \
      STATE_DIR="$TEST_ROOT/state" bash "$SCRIPT" "$ARCHIVE"
  fi
}

run_restore_forced_no_backup() {
  local backup_dir="$1"
  if [[ $EUID -eq 0 ]]; then
    run env RESTORE_FORCE=1 RESTORE_ALLOW_NO_BACKUP=1 BACKUP_DIR="$backup_dir" \
      DEST="$TEST_ROOT/dest" STATE_DIR="$TEST_ROOT/state" bash "$SCRIPT" "$ARCHIVE"
  else
    sudo -n true >/dev/null 2>&1 || skip "requer root ou sudo sem senha"
    run sudo -n env RESTORE_FORCE=1 RESTORE_ALLOW_NO_BACKUP=1 BACKUP_DIR="$backup_dir" \
      DEST="$TEST_ROOT/dest" STATE_DIR="$TEST_ROOT/state" bash "$SCRIPT" "$ARCHIVE"
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

@test "restore rejects an archive without any known configuration item" {
  printf 'x\n' >"$TEST_ROOT/src/unrelated"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" unrelated

  run_restore
  [ "$status" -eq 1 ]
  [[ "$output" == *"não contém"* ]]
  [ ! -e "$TEST_ROOT/dest" ]
}

@test "restore fails closed when BACKUP_DIR is a regular file" {
  mkdir -p "$TEST_ROOT/dest/dynamic"
  printf 'old\n' >"$TEST_ROOT/dest/dynamic/platform.yml"
  printf 'new:\n' >"$TEST_ROOT/src/dynamic/platform.yml"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" dynamic
  printf 'not a directory\n' >"$TEST_ROOT/backup-dir"

  run_restore_forced "$TEST_ROOT/backup-dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BACKUP_DIR"* ]]
  [ "$(cat "$TEST_ROOT/dest/dynamic/platform.yml")" = "old" ]
}

@test "restore creates a verified pre-restore backup before replacing files" {
  mkdir -p "$TEST_ROOT/dest/dynamic"
  printf 'old\n' >"$TEST_ROOT/dest/dynamic/platform.yml"
  printf 'new:\n' >"$TEST_ROOT/src/dynamic/platform.yml"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" dynamic
  mkdir -p "$TEST_ROOT/backups"

  run_restore_forced "$TEST_ROOT/backups"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/dest/dynamic/platform.yml")" = "new:" ]

  backup="$(find "$TEST_ROOT/backups" -maxdepth 1 -name 'pre-restore-*.tar.gz' -print -quit)"
  [ -n "$backup" ]
  [ -f "$backup.sha256" ]
  tar tzf "$backup" >"$TEST_ROOT/backup-list"
  grep -q '^dynamic/platform.yml$' "$TEST_ROOT/backup-list"
  ( cd "$TEST_ROOT/backups" && sha256sum -c "$(basename "$backup").sha256" >/dev/null )
}

@test "restore requires an explicit override to skip the pre-restore backup" {
  mkdir -p "$TEST_ROOT/dest/dynamic"
  printf 'old\n' >"$TEST_ROOT/dest/dynamic/platform.yml"
  printf 'new:\n' >"$TEST_ROOT/src/dynamic/platform.yml"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" dynamic
  mkdir -p "$TEST_ROOT/backups"

  run_restore_forced_no_backup "$TEST_ROOT/backups"
  [ "$status" -eq 0 ]
  [[ "$output" == *"desativado"* ]]
  grep -q 'IGNORADO' "$TEST_ROOT/backups/restore-audit.log"
  [ -z "$(find "$TEST_ROOT/backups" -maxdepth 1 -name 'pre-restore-*.tar.gz' -print -quit)" ]
}


@test "restore aborts when the audit log cannot be written" {
  printf 'new:\n' >"$TEST_ROOT/src/dynamic/platform.yml"
  tar czf "$ARCHIVE" -C "$TEST_ROOT/src" dynamic
  mkdir -p "$TEST_ROOT/dest/dynamic" "$TEST_ROOT/backups"
  printf 'old\n' >"$TEST_ROOT/dest/dynamic/platform.yml"

  if [[ $EUID -eq 0 ]]; then
    run env RESTORE_FORCE=1 RESTORE_ALLOW_NO_BACKUP=1 BACKUP_DIR="$TEST_ROOT/backups" \
      AUDIT_LOG=/dev/full DEST="$TEST_ROOT/dest" STATE_DIR="$TEST_ROOT/state" \
      bash "$SCRIPT" "$ARCHIVE"
  else
    sudo -n true >/dev/null 2>&1 || skip "requer root ou sudo sem senha"
    run sudo -n env RESTORE_FORCE=1 RESTORE_ALLOW_NO_BACKUP=1 BACKUP_DIR="$TEST_ROOT/backups" \
      AUDIT_LOG=/dev/full DEST="$TEST_ROOT/dest" STATE_DIR="$TEST_ROOT/state" \
      bash "$SCRIPT" "$ARCHIVE"
  fi
  [ "$status" -eq 1 ]
  [[ "$output" == *"auditoria"* ]]
  [ "$(cat "$TEST_ROOT/dest/dynamic/platform.yml")" = "old" ]
}
