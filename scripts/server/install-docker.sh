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

DAEMON_JSON=/etc/docker/daemon.json
install -d -m 0755 /etc/docker
if [[ -f "$DAEMON_JSON" ]]; then
  cp -a "$DAEMON_JSON" "$DAEMON_JSON.bak.$(date -u +%Y%m%dT%H%M%SZ)"
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

if [[ -f "$DAEMON_JSON" ]]; then
  command -v python3 >/dev/null 2>&1 \
    || { echo "ERRO: $DAEMON_JSON já existe e python3 não está disponível para mesclar sem perder configurações." >&2; exit 1; }
  DOCKER_DAEMON_JSON="$DAEMON_JSON" \
  DOCKER_ADDRESS_POOL="$DOCKER_ADDRESS_POOL" \
  DOCKER_ADDRESS_POOL_SIZE="$DOCKER_ADDRESS_POOL_SIZE" \
  DOCKER_ICC="$DOCKER_ICC" \
  DOCKER_USERLAND_PROXY="$DOCKER_USERLAND_PROXY" \
  python3 - <<'PY'
import json
import os
import sys

path = os.environ["DOCKER_DAEMON_JSON"]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    print(f"ERRO: não foi possível ler {path}: {exc}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict):
    print(f"ERRO: {path} deve conter um objeto JSON", file=sys.stderr)
    sys.exit(1)

log_opts = data.get("log-opts")
if not isinstance(log_opts, dict):
    log_opts = {}
log_opts["max-size"] = "10m"
log_opts["max-file"] = "3"
data["log-driver"] = "json-file"
data["log-opts"] = log_opts
data["icc"] = os.environ["DOCKER_ICC"] == "true"
data["userland-proxy"] = os.environ["DOCKER_USERLAND_PROXY"] == "true"
data["default-address-pools"] = [
    {
        "base": os.environ["DOCKER_ADDRESS_POOL"],
        "size": int(os.environ["DOCKER_ADDRESS_POOL_SIZE"]),
    }
]

tmp = f"{path}.tmp"
try:
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
except OSError as exc:
    print(f"ERRO: não foi possível gravar {path}: {exc}", file=sys.stderr)
    try:
        os.unlink(tmp)
    except OSError:
        pass
    sys.exit(1)
PY
  echo "daemon.json existente mesclado: chaves gerenciadas atualizadas, demais preservadas" >&2
else
  cat >"$DAEMON_JSON" <<EOF
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
fi
chmod 0644 "$DAEMON_JSON"

systemctl enable docker
systemctl restart docker

if ! id deployer >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/deployer --shell /usr/sbin/nologin deployer
fi
usermod -aG docker deployer

echo "Docker instalado. ATENÇÃO: pertencer ao grupo docker equivale a root no host."
