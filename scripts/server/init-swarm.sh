#!/usr/bin/env bash
# Initializes a single-node Swarm manager with autolock enabled.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker não instalado" >&2; exit 1; }

default_addr() {
  hostname -I | tr ' ' '\n' | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }'
}
ADVERTISE_ADDR="${1:-${SWARM_ADVERTISE_ADDR:-$(default_addr)}}"
[[ "$ADVERTISE_ADDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
  || { echo "endereço de anúncio inválido: $ADVERTISE_ADDR" >&2; exit 2; }

print_unlock_key() {
  if ! docker swarm unlock-key; then
    echo "AVISO: autolock não está habilitado; rode 'docker swarm update --autolock=true'." >&2
  fi
}

state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
if [[ "$state" == "active" ]]; then
  echo "Swarm já está ativo neste nó."
  print_unlock_key
  exit 0
fi
if [[ -n "$state" && "$state" != "inactive" ]]; then
  echo "Swarm está em estado '$state'; resolva antes de inicializar." >&2
  exit 1
fi

docker swarm init --advertise-addr "$ADVERTISE_ADDR" --autolock
print_unlock_key
echo "Guarde a chave de desbloqueio no cofre; ela será exigida após reinícios."
