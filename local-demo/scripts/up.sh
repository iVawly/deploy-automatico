#!/usr/bin/env bash
# Brings up the local demo: Swarm, networks, secrets, platform and the pilot app.
set -Eeuo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_ROOT="$(cd "$DEMO_ROOT/.." && pwd)"
DEMO_WIN="$(cygpath -m "$DEMO_ROOT")"
PLATFORM_WIN="$(cygpath -m "$PLATFORM_ROOT")"
STACK="${DEMO_STACK:-demo-platform}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker não encontrado"
command -v cygpath >/dev/null 2>&1 || die "execute no Git Bash"
docker info >/dev/null 2>&1 || die "Docker Desktop não está rodando"

log "verificando Swarm"
if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]]; then
  docker swarm init >/dev/null
fi

for network in public internal; do
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    log "criando rede $network"
    docker network create --driver overlay --attachable "$network" >/dev/null
  fi
done

CREDS_FILE="$DEMO_ROOT/state/credentials.env"

if [[ -f "$CREDS_FILE" ]]; then
  # shellcheck source=/dev/null
  . "$CREDS_FILE"
  for var in TRAEFIK_ADMIN_USER TRAEFIK_ADMIN_PASSWORD GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD; do
    [[ -n "${!var:-}" ]] || die "$CREDS_FILE não define $var"
  done
elif docker secret inspect traefik_dashboard_users >/dev/null 2>&1 ||
     docker secret inspect grafana_admin_password >/dev/null 2>&1; then
  die "segredos antigos encontrados sem $CREDS_FILE; remova-os para gerar credenciais novas"
fi

TRAEFIK_ADMIN_USER="${TRAEFIK_ADMIN_USER:-demo-$(openssl rand -hex 3)}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-demo-$(openssl rand -hex 3)}"
TRAEFIK_ADMIN_PASSWORD="${TRAEFIK_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\r\n')}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\r\n')}"

[[ "$TRAEFIK_ADMIN_USER" =~ ^[A-Za-z0-9._-]+$ ]] || die "TRAEFIK_ADMIN_USER inválido"
[[ "$GRAFANA_ADMIN_USER" =~ ^[A-Za-z0-9._-]+$ ]] || die "GRAFANA_ADMIN_USER inválido"

if ! docker secret inspect traefik_dashboard_users >/dev/null 2>&1; then
  log "criando segredo do dashboard (usuário $TRAEFIK_ADMIN_USER)"
  hash="$(printf '%s\n' "$TRAEFIK_ADMIN_PASSWORD" | openssl passwd -apr1 -stdin)"
  printf '%s:%s\n' "$TRAEFIK_ADMIN_USER" "$hash" | docker secret create traefik_dashboard_users - >/dev/null
fi
if ! docker secret inspect grafana_admin_password >/dev/null 2>&1; then
  log "criando segredo do Grafana (usuário $GRAFANA_ADMIN_USER)"
  printf '%s' "$GRAFANA_ADMIN_PASSWORD" | docker secret create grafana_admin_password - >/dev/null
fi

mkdir -p "$DEMO_ROOT/state"
(
  umask 077
  {
    printf 'TRAEFIK_ADMIN_USER=%q\n' "$TRAEFIK_ADMIN_USER"
    printf 'TRAEFIK_ADMIN_PASSWORD=%q\n' "$TRAEFIK_ADMIN_PASSWORD"
    printf 'GRAFANA_ADMIN_USER=%q\n' "$GRAFANA_ADMIN_USER"
    printf 'GRAFANA_ADMIN_PASSWORD=%q\n' "$GRAFANA_ADMIN_PASSWORD"
  } >"$CREDS_FILE"
)
chmod 600 "$CREDS_FILE" 2>/dev/null || true

log "renderizando e implantando a stack $STACK"
sed "s|\${DEMO_ROOT}|$DEMO_WIN|g; s|\${PLATFORM_ROOT}|$PLATFORM_WIN|g; s|\${GRAFANA_ADMIN_USER}|$GRAFANA_ADMIN_USER|g" \
  "$DEMO_ROOT/platform.yml" >"$DEMO_ROOT/platform.rendered.yml"
docker stack deploy -c "$DEMO_WIN/platform.rendered.yml" "$STACK" >/dev/null

log "aguardando o registry local"
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:5000/v2/ >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS http://127.0.0.1:5000/v2/ >/dev/null 2>&1 || die "registry não respondeu na porta 5000"

log "construindo e publicando imagens da aplicação"
docker build -t 127.0.0.1:5000/demo-app:1.0.0 "$PLATFORM_WIN/apps/demo-app" >/dev/null
docker build -t 127.0.0.1:5000/demo-app:1.0.1 "$PLATFORM_WIN/apps/demo-app" >/dev/null
docker build --build-arg DEPENDENCY_URL=http://127.0.0.1:1/health \
  -t 127.0.0.1:5000/demo-app:2.0.0 "$PLATFORM_WIN/apps/demo-app" >/dev/null
for version in 1.0.0 1.0.1 2.0.0; do
  docker push "127.0.0.1:5000/demo-app:$version" >/dev/null
done

log "aguardando o Traefik"
for _ in $(seq 1 60); do
  if curl -ksS https://traefik.127.0.0.1.nip.io/ -o /dev/null 2>/dev/null; then
    break
  fi
  sleep 2
done

if bash "$DEMO_ROOT/scripts/ops" status demo-app --json 2>/dev/null | grep -q '"active_version":""'; then
  log "primeiro deploy (bootstrap 1.0.0)"
  bash "$DEMO_ROOT/scripts/ops" bootstrap demo-app 1.0.0
else
  log "release estável já registrada; verificando a versão ativa"
  if ! bash "$DEMO_ROOT/scripts/ops" verify demo-app --quiet; then
    log "serviço ativo ausente ou não saudável; recriando a partir do ledger"
    bash "$DEMO_ROOT/scripts/ops" recover demo-app ||
      die "não foi possível recuperar a versão ativa; consulte 'ops status demo-app'"
  fi
fi

log "pronto"
cat <<EOF
App:      https://demo.127.0.0.1.nip.io/
Health:   bash local-demo/scripts/ops verify demo-app (interno)
Traefik:  https://traefik.127.0.0.1.nip.io/ (usuário $TRAEFIK_ADMIN_USER; senha em local-demo/state/credentials.env)
Monitor:  https://monitor.127.0.0.1.nip.io/ (crie a conta na primeira abertura)
Grafana:  https://grafana.127.0.0.1.nip.io/ (usuário $GRAFANA_ADMIN_USER; senha em local-demo/state/credentials.env)

O certificado é autoassinado: aceite o aviso do navegador.
Execute local-demo/scripts/demo.sh para o roteiro de deploy, falha e rollback.
EOF
