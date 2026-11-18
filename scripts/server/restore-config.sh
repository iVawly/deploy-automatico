#!/usr/bin/env bash
# Restores a configuration backup created by backup-config.sh.
# Usage: sudo RESTORE_FORCE=1 /opt/deploy-platform/scripts/server/restore-config.sh <arquivo.tar.gz>
set -Eeuo pipefail
umask 077

die() { echo "ERRO: $*" >&2; exit 1; }
warn() { echo "AVISO: $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }
ARCHIVE="${1:-}"
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || { echo "uso: $0 <arquivo.tar.gz>" >&2; exit 2; }

DEST="${DEST:-/opt/deploy-platform}"
STATE_DIR="${STATE_DIR:-/var/lib/ops-deploy}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/ops-deploy}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
AUDIT_LOG="${AUDIT_LOG:-$BACKUP_DIR/restore-audit.log}"

audit() {
  local dir
  dir="$(dirname "$AUDIT_LOG")"
  mkdir -p "$dir" \
    || die "não foi possível criar o diretório do log de auditoria: $dir"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$AUDIT_LOG" \
    || die "não foi possível gravar o log de auditoria em $AUDIT_LOG"
  chmod 600 "$AUDIT_LOG" \
    || die "não foi possível ajustar as permissões do log de auditoria $AUDIT_LOG"
}

if [[ -f "$ARCHIVE.sha256" ]]; then
  expected="$(awk 'NR==1 {print $1}' "$ARCHIVE.sha256")"
  actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
  [[ "$expected" =~ ^[0-9a-f]{64}$ && "$expected" == "$actual" ]] \
    || die "checksum de $ARCHIVE não confere."
else
  warn "checksum $ARCHIVE.sha256 não encontrado; seguindo sem verificação."
fi

LISTING="$(mktemp)"
TYPES="$(mktemp)"
STAGE=""
trap '[[ -n "$STAGE" ]] && rm -rf "$STAGE"; rm -f "$LISTING" "$TYPES"' EXIT

tar tzf "$ARCHIVE" >"$LISTING" || die "não foi possível ler $ARCHIVE."
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$LISTING"; then
  die "arquivo contém caminhos absolutos ou '..'; recusando."
fi
tar tvzf "$ARCHIVE" >"$TYPES" || die "não foi possível inspecionar os tipos de $ARCHIVE."
bad_types="$(awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { print }' "$TYPES")"
if [[ -n "$bad_types" ]]; then
  die "arquivo contém symlink, hardlink ou tipo especial; recusando."
fi

restore_items=()
for item in dynamic deploy runbooks docs; do
  if grep -Eq "^${item}(/|$)" "$LISTING"; then
    restore_items+=("$item")
  fi
done
has_env=0
if grep -Fxq ".env" "$LISTING"; then has_env=1; fi
has_ledger=0
if grep -Fxq "var/lib/ops-deploy/releases.jsonl" "$LISTING"; then has_ledger=1; fi
if [[ ${#restore_items[@]} -eq 0 && "$has_env" -eq 0 && "$has_ledger" -eq 0 ]]; then
  die "backup não contém dynamic, deploy, runbooks, docs, .env ou ledger; recusando."
fi

if [[ "${RESTORE_FORCE:-0}" != "1" ]]; then
  echo "Simulação: o backup é válido, mas nada foi restaurado." >&2
  echo "Defina RESTORE_FORCE=1 para sobrescrever $DEST e $STATE_DIR." >&2
  exit 0
fi

if ! mkdir -p "$DEST" "$STATE_DIR" "$BACKUP_DIR"; then
  die "não foi possível preparar $DEST, $STATE_DIR ou $BACKUP_DIR (BACKUP_DIR precisa ser um diretório)."
fi

pre_restore_backup() {
  local item dest_archive tmp listing hash missing=""
  local -a items=()
  for item in dynamic deploy runbooks docs; do
    [[ -e "$DEST/$item" ]] && items+=("$item")
  done
  [[ -f "$DEST/.env" ]] && items+=(.env)

  if [[ "${RESTORE_ALLOW_NO_BACKUP:-0}" == "1" ]]; then
    warn "RESTORE_ALLOW_NO_BACKUP=1: backup pré-restauração desativado por escolha explícita."
    audit "backup pre-restauracao IGNORADO via RESTORE_ALLOW_NO_BACKUP=1 (itens: ${items[*]:-nenhum})"
    return 0
  fi
  if [[ ${#items[@]} -eq 0 ]]; then
    warn "nada a preservar em $DEST (sem dynamic/deploy/runbooks/docs/.env)."
    audit "backup pre-restauracao sem itens"
    return 0
  fi

  dest_archive="$BACKUP_DIR/pre-restore-$STAMP.tar.gz"
  tmp="$(mktemp "$BACKUP_DIR/.pre-restore-$STAMP.XXXXXX")"
  if ! tar czf "$tmp" -C "$DEST" "${items[@]}"; then
    rm -f "$tmp"
    die "falha ao criar backup pré-restauração; nada foi restaurado."
  fi
  if ! listing="$(tar tzf "$tmp")"; then
    rm -f "$tmp"
    die "backup pré-restauração ilegível; nada foi restaurado."
  fi
  for item in "${items[@]}"; do
    if [[ "$item" == ".env" ]]; then
      printf '%s\n' "$listing" | grep -Fxq ".env" || missing+=" .env"
    else
      printf '%s\n' "$listing" | grep -Eq "^${item}(/|$)" || missing+=" $item"
    fi
  done
  if [[ -n "$missing" ]]; then
    rm -f "$tmp"
    die "backup pré-restauração incompleto (faltando:$missing); nada foi restaurado."
  fi
  chmod 600 "$tmp"
  hash="$(sha256sum "$tmp" | awk '{print $1}')"
  mv "$tmp" "$dest_archive" || { rm -f "$tmp"; die "falha ao finalizar o backup pré-restauração."; }
  printf '%s  %s\n' "$hash" "$(basename "$dest_archive")" >"$dest_archive.sha256"
  chmod 600 "$dest_archive" "$dest_archive.sha256"
  audit "backup pre-restauracao criado: $dest_archive"
}

backup_ledger() {
  local src="$STATE_DIR/releases.jsonl" dst="$BACKUP_DIR/releases-pre-restore-$STAMP.jsonl"
  [[ -f "$src" ]] || return 0
  if [[ "${RESTORE_ALLOW_NO_BACKUP:-0}" == "1" ]]; then
    warn "RESTORE_ALLOW_NO_BACKUP=1: backup do ledger desativado por escolha explícita."
    audit "backup do ledger IGNORADO via RESTORE_ALLOW_NO_BACKUP=1"
    return 0
  fi
  cp -a "$src" "$dst" || die "falha ao preservar o ledger; nada foi restaurado."
  chmod 600 "$dst" 2>/dev/null || true
  audit "backup do ledger criado: $dst"
}

restore_dir_item() {
  local item="$1" src="$STAGE/$1" dest="$DEST/$1" tmp old
  tmp="$(mktemp -d "$DEST/.restore-$item.XXXXXX")"
  if ! cp -a "$src/." "$tmp/"; then
    rm -rf "$tmp"
    die "falha ao preparar $item; nada foi movido."
  fi
  old="$DEST/.old-$item.$STAMP"
  if [[ -e "$dest" ]]; then
    mv "$dest" "$old" || { rm -rf "$tmp"; die "falha ao mover $item antigo; nada foi alterado."; }
  fi
  if ! mv "$tmp" "$dest"; then
    if [[ -e "$old" ]]; then
      mv "$old" "$dest" || true
    fi
    rm -rf "$tmp"
    die "falha ao ativar $item restaurado; versão anterior preservada."
  fi
  [[ -e "$old" ]] && rm -rf "$old"
  audit "restaurado: $item"
  return 0
}

install_atomic() {
  local src="$1" dst="$2" mode="$3" owner="${4:-}" tmp
  tmp="$(mktemp "$(dirname "$dst")/.$(basename "$dst").restore.XXXXXX")"
  if ! install -m "$mode" "$src" "$tmp"; then
    rm -f "$tmp"
    die "falha ao preparar $dst."
  fi
  if ! mv "$tmp" "$dst"; then
    rm -f "$tmp"
    die "falha ao ativar $dst."
  fi
  if [[ -n "$owner" ]]; then
    chown "$owner" "$dst" 2>/dev/null || true
  fi
}

STAGE="$(mktemp -d)"
tar --no-same-owner -xzf "$ARCHIVE" -C "$STAGE" || die "falha ao extrair $ARCHIVE."

pre_restore_backup
backup_ledger

for item in "${restore_items[@]}"; do
  restore_dir_item "$item"
done

if [[ -f "$STAGE/.env" ]]; then
  install_atomic "$STAGE/.env" "$DEST/.env" 0600 root:root
  warn ".env restaurado do backup; confira DOMAIN, ACME_EMAIL e segredos."
  audit "restaurado: .env"
fi

if [[ -f "$STAGE/var/lib/ops-deploy/releases.jsonl" ]]; then
  install_atomic "$STAGE/var/lib/ops-deploy/releases.jsonl" "$STATE_DIR/releases.jsonl" 0600 deployer:deployer
  audit "restaurado: ledger"
fi

echo "configuração restaurada em $DEST; ledger em $STATE_DIR/releases.jsonl"
echo "rode /opt/deploy-platform/scripts/server/install-docker.sh e sudo /opt/deploy-platform/scripts/bootstrap-platform.sh para reaplicar o runtime."
