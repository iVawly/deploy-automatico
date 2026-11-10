#!/usr/bin/env bash
# Installs Docker Engine and creates the unprivileged deployer account used by the runner.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl --proto '=https' --tlsv1.2 -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck source=/dev/null
  . /etc/os-release
  [[ -n "${VERSION_CODENAME:-}" ]] \
    || { echo "não foi possível detectar VERSION_CODENAME em /etc/os-release" >&2; exit 1; }
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

install -d -m 0755 /etc/docker
if [[ -f /etc/docker/daemon.json ]]; then
  cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  echo "daemon.json existente preservado como backup" >&2
fi

# Override these when the defaults conflict with a VPN or an existing network.
DOCKER_ADDRESS_POOL="${DOCKER_ADDRESS_POOL:-172.30.0.0/16}"
DOCKER_ADDRESS_POOL_SIZE="${DOCKER_ADDRESS_POOL_SIZE:-24}"
DOCKER_ICC="${DOCKER_ICC:-false}"
DOCKER_USERLAND_PROXY="${DOCKER_USERLAND_PROXY:-false}"

[[ "$DOCKER_ADDRESS_POOL" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] \
  || { echo "DOCKER_ADDRESS_POOL inválido: $DOCKER_ADDRESS_POOL (use CIDR, ex.: 172.30.0.0/16)" >&2; exit 1; }
[[ "$DOCKER_ADDRESS_POOL_SIZE" =~ ^[0-9]{1,2}$ ]] \
  || { echo "DOCKER_ADDRESS_POOL_SIZE inválido: $DOCKER_ADDRESS_POOL_SIZE" >&2; exit 1; }
pool_prefix="${DOCKER_ADDRESS_POOL#*/}"
(( 10#$DOCKER_ADDRESS_POOL_SIZE >= 10#$pool_prefix && 10#$DOCKER_ADDRESS_POOL_SIZE <= 32 )) \
  || { echo "DOCKER_ADDRESS_POOL_SIZE inválido: deve ficar entre $pool_prefix e 32" >&2; exit 1; }
[[ "$DOCKER_ICC" =~ ^(true|false)$ ]] \
  || { echo "DOCKER_ICC inválido: $DOCKER_ICC (use true ou false)" >&2; exit 1; }
[[ "$DOCKER_USERLAND_PROXY" =~ ^(true|false)$ ]] \
  || { echo "DOCKER_USERLAND_PROXY inválido: $DOCKER_USERLAND_PROXY (use true ou false)" >&2; exit 1; }

cat >/etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "icc": $DOCKER_ICC,
  "userland-proxy": $DOCKER_USERLAND_PROXY,
  "default-address-pools": [
    {
      "base": "$DOCKER_ADDRESS_POOL",
      "size": $DOCKER_ADDRESS_POOL_SIZE
    }
  ]
}
EOF
chmod 0644 /etc/docker/daemon.json

systemctl enable docker
systemctl restart docker

if ! id deployer >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/deployer --shell /usr/sbin/nologin deployer
fi
usermod -aG docker deployer

echo "Docker instalado. ATENÇÃO: pertencer ao grupo docker equivale a root no host."
