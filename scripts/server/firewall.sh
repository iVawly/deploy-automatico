#!/usr/bin/env bash
# Enables a default-deny firewall allowing only SSH (rate limited), HTTP and HTTPS.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

SSH_PORT="${SSH_PORT:-22}"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || { echo "SSH_PORT inválido: $SSH_PORT" >&2; exit 1; }

command -v ufw >/dev/null 2>&1 || {
  apt-get update
  apt-get install -y ufw
}

ufw default deny incoming
ufw default deny routed
ufw default allow outgoing
ufw logging on
ufw limit "${SSH_PORT}/tcp" comment 'ssh (rate limited)'
ufw allow 80/tcp comment 'http'
ufw allow 443/tcp comment 'https'
ufw --force enable

ufw status verbose
