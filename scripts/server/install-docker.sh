#!/usr/bin/env bash
# Installs Docker Engine and creates the unprivileged deployer account used by the runner.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl --proto '=https' --tlsv1.2 -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck source=/dev/null
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

install -d -m 0755 /etc/docker
if [[ -f /etc/docker/daemon.json ]]; then
  cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  echo "daemon.json existente preservado como backup" >&2
fi
cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "icc": false,
  "userland-proxy": false,
  "default-address-pools": [
    {
      "base": "172.30.0.0/16",
      "size": 24
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
