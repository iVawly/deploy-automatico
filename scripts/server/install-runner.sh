#!/usr/bin/env bash
# Installs a GitHub Actions self-hosted runner as a systemd service under deployer.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

: "${RUNNER_URL:?defina RUNNER_URL (ex.: https://github.com/sua-org)}"
: "${RUNNER_TOKEN:?defina RUNNER_TOKEN (token de registro, válido por 1 hora)}"
RUNNER_VERSION="${RUNNER_VERSION:-2.338.2}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-deploy}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,deploy}"
RUNNER_DIR="/opt/actions-runner"

case "$RUNNER_VERSION" in
  2.338.2)
    RUNNER_SHA256="${RUNNER_SHA256:-baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40}"
    ;;
  *)
    : "${RUNNER_SHA256:?defina RUNNER_SHA256 para a versão $RUNNER_VERSION (veja as notas da release)}"
    ;;
esac

id deployer >/dev/null 2>&1 || {
  echo "usuário deployer não existe; execute install-docker.sh primeiro" >&2
  exit 1
}

if [[ ! -f "$RUNNER_DIR/config.sh" ]]; then
  mkdir -p "$RUNNER_DIR"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/runner.tar.gz" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  printf '%s  %s\n' "$RUNNER_SHA256" "$tmp/runner.tar.gz" | sha256sum -c -
  tar xzf "$tmp/runner.tar.gz" -C "$RUNNER_DIR" --no-same-owner
  rm -rf "$tmp"
  trap - EXIT
  "$RUNNER_DIR/bin/installdependencies.sh"
fi

chown -R deployer:deployer "$RUNNER_DIR"

if [[ ! -f "$RUNNER_DIR/.runner" ]]; then
  (
    cd "$RUNNER_DIR"
    sudo -u deployer ./config.sh \
      --unattended \
      --url "$RUNNER_URL" \
      --token "$RUNNER_TOKEN" \
      --name "$RUNNER_NAME" \
      --labels "$RUNNER_LABELS" \
      --work _work \
      --disableupdate \
      --replace
  )
fi

(
  cd "$RUNNER_DIR"
  ./svc.sh install deployer
  ./svc.sh start
)

echo "Runner instalado. Verifique: systemctl status actions.runner.* --no-pager"
echo "Atualizações do runner são intencionais: mude RUNNER_VERSION/RUNNER_SHA256 e reinstale."
