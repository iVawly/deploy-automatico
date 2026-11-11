#!/usr/bin/env bash
# Restores a configuration backup created by backup-config.sh into a staging tree.
# Usage: sudo RESTORE_FORCE=1 /opt/deploy-platform/scripts/server/restore-config.sh <arquivo.tar.gz>
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }
ARCHIVE="${1:-}"
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || { echo "uso: $0 <arquivo.tar.gz>" >&2; exit 2; }

DEST="${DEST:-/opt/deploy-platform}"
STATE_DIR="${STATE_DIR:-/var/lib/ops-deploy}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -f "$ARCHIVE.sha256" ]]; then
  expected="$(awk 'NR==1 {print $1}' "$ARCHIVE.sha256")"
  actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
  [[ "$expected" =~ ^[0-9a-f]{64}$ && "$expected" == "$actual" ]] \
    || { echo "ERRO: checksum de $ARCHIVE não confere." >&2; exit 1; }
else
  echo "AVISO: checksum $ARCHIVE.sha256 não encontrado; seguindo sem verificação." >&2
fi

LISTING="$(mktemp)"
TYPES="$(mktemp)"
STAGE=""
trap 'rm -rf "$STAGE" "$LISTING" "$TYPES"' EXIT
if ! tar tzf "$ARCHIVE" >"$LISTING"; then
  echo "ERRO: não foi possível ler $ARCHIVE." >&2
  exit 1
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$LISTING"; then
  echo "ERRO: arquivo contém caminhos absolutos ou '..'; recusando." >&2
  exit 1
fi
if ! tar tvzf "$ARCHIVE" >"$TYPES"; then
  echo "ERRO: não foi possível inspecionar os tipos de $ARCHIVE." >&2
  exit 1
fi
bad_types="$(awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { print }' "$TYPES")"
if [[ -n "$bad_types" ]]; then
  echo "ERRO: arquivo contém symlink, hardlink ou tipo especial; recusando." >&2
  exit 1
fi

if [[ "${RESTORE_FORCE:-0}" != "1" ]]; then
  echo "Simulação: o backup é válido, mas nada foi restaurado." >&2
  echo "Defina RESTORE_FORCE=1 para sobrescrever $DEST e $STATE_DIR." >&2
  exit 0
fi

STAGE="$(mktemp -d)"
tar --no-same-owner -xzf "$ARCHIVE" -C "$STAGE"

mkdir -p "$DEST" "$STATE_DIR" /var/backups/ops-deploy
if [[ -d "$DEST/dynamic" || -d "$DEST/deploy" ]]; then
  pre_items=(dynamic deploy runbooks docs)
  [[ -f "$DEST/.env" ]] && pre_items+=(.env)
  tar czf "/var/backups/ops-deploy/pre-restore-$STAMP.tar.gz" \
    -C "$DEST" "${pre_items[@]}" 2>/dev/null || true
fi
if [[ -f "$STATE_DIR/releases.jsonl" ]]; then
  cp -a "$STATE_DIR/releases.jsonl" "/var/backups/ops-deploy/releases-pre-restore-$STAMP.jsonl"
fi

for item in dynamic deploy runbooks docs; do
  [[ -e "$STAGE/$item" ]] || continue
  rm -rf "${DEST:?}/$item"
  cp -a "$STAGE/$item" "$DEST/$item"
done

if [[ -f "$STAGE/.env" ]]; then
  install -m 0600 "$STAGE/.env" "$DEST/.env"
  chown root:root "$DEST/.env" 2>/dev/null || true
  echo "AVISO: .env restaurado do backup; confira DOMAIN, ACME_EMAIL e segredos." >&2
fi

if [[ -f "$STAGE/var/lib/ops-deploy/releases.jsonl" ]]; then
  install -m 0600 "$STAGE/var/lib/ops-deploy/releases.jsonl" "$STATE_DIR/releases.jsonl"
  chown deployer:deployer "$STATE_DIR/releases.jsonl" 2>/dev/null || true
fi

echo "configuração restaurada em $DEST; ledger em $STATE_DIR/releases.jsonl"
echo "rode /opt/deploy-platform/scripts/server/install-docker.sh e sudo /opt/deploy-platform/scripts/bootstrap-platform.sh para reaplicar o runtime."
