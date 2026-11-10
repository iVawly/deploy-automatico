#!/usr/bin/env bash
# Backs up platform configuration, generated routes and the release ledger.
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/ops-deploy}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/ops-deploy-config-$STAMP.tar.gz"

[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || { echo "BACKUP_RETENTION_DAYS inválido" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"

tar_args=(-C "$ROOT" dynamic deploy runbooks docs)
if [[ "${BACKUP_INCLUDE_ENV:-0}" == "1" ]]; then
  if [[ -f "$ROOT/.env" ]]; then
    tar_args+=(.env)
  else
    echo "AVISO: BACKUP_INCLUDE_ENV=1, mas $ROOT/.env não existe" >&2
  fi
fi
if [[ -f /var/lib/ops-deploy/releases.jsonl ]]; then
  tar_args+=(-C / var/lib/ops-deploy/releases.jsonl)
fi
tar czf "$OUT" "${tar_args[@]}"
tar tzf "$OUT" >/dev/null

( cd "$BACKUP_DIR" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
chmod 600 "$OUT" "$OUT.sha256"

find "$BACKUP_DIR" -maxdepth 1 -type f -name 'ops-deploy-config-*.tar.gz*' \
  -mtime "+$RETENTION_DAYS" -delete

echo "backup criado: $OUT"
echo "checksum:     $OUT.sha256"
echo "copie ambos para fora do servidor; o arquivo contém metadados de deploy, não segredos."
if [[ "${BACKUP_INCLUDE_ENV:-0}" == "1" ]]; then
  echo "ATENÇÃO: este backup inclui .env com segredos; armazene-o cifrado e restrinja o acesso."
fi
