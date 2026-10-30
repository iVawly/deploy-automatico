# Runbook: runner do GitHub Actions

O runner roda no próprio servidor, sob o usuário `deployer`, sem shell de login. Ele inicia conexões de saída para o GitHub; nenhuma porta de entrada é aberta para o CI.

## Instalação

1. Em GitHub → Settings → Actions → Runners → New self-hosted runner, copie o token de registro (validade curta).
2. No servidor:

   ```bash
   export RUNNER_URL="https://github.com/<org>"
   export RUNNER_TOKEN="<token>"
   export RUNNER_LABELS="self-hosted,linux,deploy"
   sudo -E ./scripts/server/install-runner.sh
   ```

3. Verifique:

   ```bash
   systemctl status actions.runner.* --no-pager
   ps -ef | grep '[R]unner.Listener'
   ```

4. Dispare um workflow manual e confirme que o job foi consumido pelo runner `deploy`.

## Atualização

O script não substitui um runner já configurado. Para atualizar, gere um novo
token de registro, remova a instalação antiga e reinstale com versão e SHA-256
conferidos na release oficial:

```bash
export RUNNER_URL="https://github.com/<org>"
export RUNNER_TOKEN="<novo-token>"
sudo systemctl stop actions.runner.*
sudo rm -rf /opt/actions-runner
sudo -E RUNNER_VERSION=<nova-versao> RUNNER_SHA256=<sha256-oficial> \
  ./scripts/server/install-runner.sh
```

## Revogação

1. GitHub → Settings → Actions → Runners → selecione o runner → Remove.
2. No servidor:

   ```bash
   sudo /opt/actions-runner/svc.sh stop
   sudo /opt/actions-runner/svc.sh uninstall
   sudo rm -rf /opt/actions-runner
   ```

3. Confirme que os workflows deixam de encontrar o runner.

## Diagnóstico

```bash
journalctl -u 'actions.runner.*' -n 100 --no-pager
sudo -u deployer /opt/actions-runner/run.sh --check
```

Falhas comuns:

- token expirado: gerar novo token e reconfigurar;
- sem acesso ao Docker: confirmar que `deployer` está no grupo `docker` e que o serviço foi reiniciado após a mudança;
- disco cheio: limpar `_work` e imagens antigas.

## Segurança

Pertencer ao grupo `docker` equivale a root. Não adicione outros usuários ao grupo sem necessidade, não use o runner para jobs de repositórios não confiáveis e mantenha as permissões do workflow no mínimo (`contents: read`, `packages: write`).
