#!/usr/bin/env bash
# Installs the deploy platform runtime under /opt and the CLI under /usr/local/bin.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${INSTALL_DIR:-/opt/deploy-platform}"
STATE_DIR="${STATE_DIR:-/var/lib/ops-deploy}"

id deployer >/dev/null 2>&1 || {
  echo "usuário deployer não existe; execute scripts/server/install-docker.sh primeiro" >&2
  exit 1
}

install -d -m 0755 "$DEST" "$DEST/dynamic" /var/backups/ops-deploy
install -d -o deployer -g deployer -m 0750 "$STATE_DIR" /var/log/ops-deploy

if [[ -d /etc/logrotate.d ]]; then
  cat >/etc/logrotate.d/ops-deploy <<'EOF'
/var/log/ops-deploy/*.jsonl {
  weekly
  rotate 4
  compress
  missingok
  notifempty
  create 0640 deployer deployer
}
EOF
fi

if [[ "$(cd "$ROOT" && pwd -P)" != "$(cd "$DEST" && pwd -P)" ]]; then
  tar -C "$ROOT" -cf - \
    --exclude='./.git' \
    --exclude='./local-demo' \
    --exclude='./openspec' \
    --exclude='./tests' \
    --exclude='./apps' \
    --exclude='./.github' \
    --exclude='./dynamic' \
    --exclude='./.env' \
    --exclude='./.env.local' \
    --exclude='*.tar.gz' \
    . | tar -C "$DEST" -xf -
fi

install -d -m 0755 /usr/local/bin
chmod 0755 "$DEST/scripts/ops-deploy"
ln -sfn "$DEST/scripts/ops-deploy" /usr/local/bin/ops-deploy
install -d -o deployer -g deployer -m 0750 "$DEST/dynamic"
chown -R deployer:deployer "$STATE_DIR"

if [[ ! -f "$DEST/.env" && -f "$DEST/.env.example" ]]; then
  install -m 0600 "$DEST/.env.example" "$DEST/.env"
  sed -i "s|^DEPLOY_ROOT=.*|DEPLOY_ROOT=$DEST|" "$DEST/.env"
  echo "criei $DEST/.env a partir do exemplo; revise antes do bootstrap." >&2
fi

echo "instalado em $DEST"
echo "CLI: /usr/local/bin/ops-deploy"
echo "próximo passo: revise $DEST/.env e execute sudo $DEST/scripts/bootstrap-platform.sh"
