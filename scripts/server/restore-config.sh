#!/usr/bin/env bash
# Restores a configuration backup created by backup-config.sh into a staging tree.
# Usage: sudo RESTORE_FORCE=1 ./scripts/server/restore-config.sh <arquivo.tar.gz>
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }
ARCHIVE="${1:-}"
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || { echo "uso: $0 <arquivo.tar.gz>" >&2; exit 2; }

DEST="${DEST:-/opt/deploy-platform}"
STATE_DIR="${STATE_DIR:-/var/lib/ops-deploy}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -f "$ARCHIVE.sha256" ]]; then
  ( cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE").sha256" )
else
  echo "AVISO: checksum $ARCHIVE.sha256 não encontrado; seguindo sem verificação." >&2
fi

LISTING="$(mktemp)"
STAGE=""
trap 'rm -rf "$STAGE" "$LISTING"' EXIT
if ! tar tzf "$ARCHIVE" >"$LISTING"; then
  echo "ERRO: não foi possível ler $ARCHIVE." >&2
  exit 1
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$LISTING"; then
  echo "ERRO: arquivo contém caminhos absolutos ou '..'; recusando." >&2
  exit 1
fi

if [[ "${RESTORE_FORCE:-0}" != "1" ]]; then
  echo "Simulação: o backup é válido, mas nada foi restaurado." >&2
  echo "Defina RESTORE_FORCE=1 para sobrescrever $DEST e $STATE_DIR." >&2
  exit 0
fi

STAGE="$(mktemp -d)"
tar xzf "$ARCHIVE" -C "$STAGE"

mkdir -p "$DEST" "$STATE_DIR" /var/backups/ops-deploy
if [[ -d "$DEST/dynamic" || -d "$DEST/deploy" ]]; then
  tar czf "/var/backups/ops-deploy/pre-restore-$STAMP.tar.gz" \
    -C "$DEST" dynamic deploy runbooks docs 2>/dev/null || true
fi
if [[ -f "$STATE_DIR/releases.jsonl" ]]; then
  cp -a "$STATE_DIR/releases.jsonl" "/var/backups/ops-deploy/releases-pre-restore-$STAMP.jsonl"
fi

for item in dynamic deploy runbooks docs; do
  [[ -e "$STAGE/$item" ]] || continue
  rm -rf "${DEST:?}/$item"
  cp -a "$STAGE/$item" "$DEST/$item"
done

if [[ -f "$STAGE/var/lib/ops-deploy/releases.jsonl" ]]; then
  install -m 0600 "$STAGE/var/lib/ops-deploy/releases.jsonl" "$STATE_DIR/releases.jsonl"
  chown deployer:deployer "$STATE_DIR/releases.jsonl" 2>/dev/null || true
fi

echo "configuração restaurada em $DEST; ledger em $STATE_DIR/releases.jsonl"
echo "rode scripts/server/install-docker.sh e scripts/bootstrap-platform.sh para reaplicar o runtime."
