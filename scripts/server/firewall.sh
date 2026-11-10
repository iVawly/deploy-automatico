#!/usr/bin/env bash
# Enables a default-deny firewall allowing only SSH (rate limited), HTTP and HTTPS.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

SSH_PORT="${SSH_PORT:-22}"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || { echo "SSH_PORT inválido: $SSH_PORT" >&2; exit 1; }

# Swarm multi-node ports are only opened from the cluster network. Leave
# SWARM_CIDR empty on single-node installs so management ports stay closed.
SWARM_CIDR="${SWARM_CIDR:-}"

command -v ufw >/dev/null 2>&1 || {
  apt-get update
  apt-get install -y --no-install-recommends ufw
}

ufw default deny incoming
ufw default deny routed
ufw default allow outgoing
ufw logging on
ufw limit "${SSH_PORT}/tcp" comment 'ssh (rate limited)'
ufw allow 80/tcp comment 'http'
ufw allow 443/tcp comment 'https'

if [[ -n "$SWARM_CIDR" ]]; then
  [[ "$SWARM_CIDR" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] \
    || { echo "SWARM_CIDR inválido: $SWARM_CIDR (use CIDR, ex.: 10.0.0.0/24)" >&2; exit 1; }
  ufw allow from "$SWARM_CIDR" to any port 2377 proto tcp comment 'swarm manager'
  ufw allow from "$SWARM_CIDR" to any port 7946 proto tcp comment 'swarm node tcp'
  ufw allow from "$SWARM_CIDR" to any port 7946 proto udp comment 'swarm node udp'
  ufw allow from "$SWARM_CIDR" to any port 4789 proto udp comment 'swarm overlay'
else
  echo "AVISO: SWARM_CIDR não definido; portas de Swarm não liberadas (single-node)" >&2
fi

ufw --force enable

ufw status verbose
