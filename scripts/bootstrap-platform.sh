#!/usr/bin/env bash
# One-time platform bootstrap on the Ubuntu server.
# Creates overlay networks, renders platform routes and deploys the platform stack.
set -Eeuo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo $0)"

REQUESTED_ROOT="${DEPLOY_ROOT:-${INSTALL_DIR:-}}"
if [[ -n "$REQUESTED_ROOT" ]]; then
  ROOT="$REQUESTED_ROOT"
elif [[ -f /opt/deploy-platform/.env ]]; then
  ROOT=/opt/deploy-platform
elif [[ -f "$SOURCE_ROOT/.env" ]]; then
  ROOT="$SOURCE_ROOT"
else
  die "execute o bootstrap a partir do diretório instalado: sudo /opt/deploy-platform/scripts/bootstrap-platform.sh"
fi
[[ -f "$ROOT/.env" ]] || die "arquivo .env não encontrado em $ROOT; crie a partir de .env.example"
cd "$ROOT"

set -a
# shellcheck source=/dev/null
. ./.env
set +a

case "$(stat -c '%a' .env 2>/dev/null || printf '600')" in
  *[1-7][0-7]) printf 'WARN: .env legível por grupo/outros; execute: chmod 600 .env\n' >&2 ;;
esac

: "${DOMAIN:?DOMAIN não definido em .env}"
: "${ACME_EMAIL:?ACME_EMAIL não definido em .env}"
: "${GRAFANA_ADMIN_USER:?GRAFANA_ADMIN_USER não definido em .env}"
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "DOMAIN inválido: use apenas letras, números, pontos e hífens"
[[ "$ACME_EMAIL" == *@*.* ]] || die "ACME_EMAIL inválido"
if [[ -n "$REQUESTED_ROOT" ]]; then
  DEPLOY_ROOT="$REQUESTED_ROOT"
else
  DEPLOY_ROOT="${DEPLOY_ROOT:-$ROOT}"
fi
[[ "$(cd "$DEPLOY_ROOT" && pwd -P)" == "$(pwd -P)" ]] \
  || die "DEPLOY_ROOT ($DEPLOY_ROOT) difere do diretório do bootstrap ($PWD); ajuste .env"
export DEPLOY_ROOT DOMAIN ACME_EMAIL GRAFANA_ADMIN_USER

command -v docker >/dev/null 2>&1 || die "docker não instalado"
docker info >/dev/null 2>&1 || die "docker daemon não está acessível"
[[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]] \
  || die "Docker Swarm não está ativo; rode 'docker swarm init' antes"

for network in public internal; do
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    echo "criando rede overlay $network"
    docker network create --driver overlay --attachable "$network"
  fi
done

ensure_secret() {
  local name="$1" value="$2" source_hint="$3"
  if docker secret inspect "$name" >/dev/null 2>&1; then
    return 0
  fi
  [[ -n "$value" ]] || die "segredo '$name' não existe e $source_hint não está definido em .env"
  printf '%s' "$value" | docker secret create "$name" - >/dev/null
  echo "segredo $name criado a partir de .env"
}

if ! docker secret inspect traefik_dashboard_users >/dev/null 2>&1; then
  : "${TRAEFIK_ADMIN_USER:?TRAEFIK_ADMIN_USER não definido em .env (necessário para criar o segredo)}"
  : "${TRAEFIK_ADMIN_PASSWORD:?TRAEFIK_ADMIN_PASSWORD não definido em .env (necessário para criar o segredo)}"
  [[ "$TRAEFIK_ADMIN_USER" =~ ^[A-Za-z0-9._-]+$ ]] || die "TRAEFIK_ADMIN_USER inválido"
  command -v openssl >/dev/null 2>&1 || die "openssl não instalado (necessário para o hash do dashboard)"
  ensure_secret traefik_dashboard_users \
    "$TRAEFIK_ADMIN_USER:$(printf '%s' "$TRAEFIK_ADMIN_PASSWORD" | openssl passwd -apr1 -stdin)" \
    "TRAEFIK_ADMIN_USER/TRAEFIK_ADMIN_PASSWORD"
fi
if ! docker secret inspect grafana_admin_password >/dev/null 2>&1; then
  : "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD não definido em .env (necessário para criar o segredo)}"
  ensure_secret grafana_admin_password "$GRAFANA_ADMIN_PASSWORD" "GRAFANA_ADMIN_PASSWORD"
fi

mkdir -p "$ROOT/dynamic"
sed "s|\${DOMAIN}|${DOMAIN}|g" "$ROOT/deploy/traefik/dynamic/platform.yml.tpl" >"$ROOT/dynamic/platform.yml"
if grep -Fq "\${DOMAIN}" "$ROOT/dynamic/platform.yml"; then
  die "falha ao renderizar $ROOT/dynamic/platform.yml: placeholder DOMAIN restante"
fi

docker stack deploy -c "$ROOT/deploy/docker-compose.yml" platform
echo "stack platform implantada. Verifique com: docker stack services platform"
