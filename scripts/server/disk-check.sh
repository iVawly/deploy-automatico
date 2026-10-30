#!/usr/bin/env bash
# Pushes a heartbeat to Uptime Kuma only while disk usage is below the threshold.
# Configure a "Push" monitor in Uptime Kuma and schedule this script via cron.
set -Eeuo pipefail

: "${UPTIME_KUMA_PUSH_URL:?defina UPTIME_KUMA_PUSH_URL}"
THRESHOLD="${DISK_THRESHOLD:-80}"

usage_percent="$(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
if [[ -z "$usage_percent" ]]; then
  echo "não foi possível ler o uso de disco" >&2
  exit 1
fi

if (( usage_percent < THRESHOLD )); then
  curl -fsS --max-time 5 "$UPTIME_KUMA_PUSH_URL" >/dev/null
else
  logger -t ops-disk "uso de disco em ${usage_percent}% (limite ${THRESHOLD}%); heartbeat não enviado"
  echo "uso de disco em ${usage_percent}% acima do limite ${THRESHOLD}%" >&2
  exit 1
fi
