# Runbook: reconstrução do servidor

Procedimento para reconstruir a base em um Ubuntu Server 24.04 limpo. Tempo estimado: 60 a 90 minutos, sem contar a migração das aplicações.

## 0. Pré-requisitos

- [ ] DNS do domínio apontando para o novo servidor (ou janela para trocar).
- [ ] Backup de configuração mais recente (`/var/backups/ops-deploy/`), fora do host.
- [ ] Chave de autolock do Swarm e segredos no cofre.
- [ ] Acesso ao GitHub para registrar o runner.
- [ ] Repositório `infra` clonado.

## 1. Usuário e acesso

```bash
adduser <operador>
usermod -aG sudo <operador>
# copie a chave pública do operador para ~<operador>/.ssh/authorized_keys
```

Teste o login por chave em outra sessão antes de seguir.

## 2. Endurecimento

```bash
sudo ./scripts/server/harden-system.sh
sudo ./scripts/server/harden-ssh.sh
sudo usermod -aG ops <operador>
sudo ./scripts/server/firewall.sh
```

Verificação: login por senha recusado; varredura externa mostra apenas
22/80/443; `systemctl is-active fail2ban auditd` retorna `active`. Se o SSH
usar outra porta, execute `SSH_PORT=<porta> sudo -E ./scripts/server/firewall.sh`.

## 3. Docker e Swarm

```bash
sudo ./scripts/server/install-docker.sh
sudo ./scripts/server/init-swarm.sh <ip-do-servidor>
```

Guarde a chave de desbloqueio exibida no cofre. Verificação:

```bash
docker info --format '{{.Swarm.LocalNodeState}}'
docker node ls
```

## 4. Segredos e configuração

```bash
export TRAEFIK_ADMIN_USER='<usuario>'
export TRAEFIK_ADMIN_PASSWORD='<senha-forte>'
printf '%s\n' "$(htpasswd -nbB "$TRAEFIK_ADMIN_USER" "$TRAEFIK_ADMIN_PASSWORD")" | sudo docker secret create traefik_dashboard_users -
openssl rand -base64 24 | sudo docker secret create grafana_admin_password -
# crie também os segredos de cada aplicação real, por exemplo:
# printf '%s' '<valor>' | sudo docker secret create demo_app_database_url -
```

Defina também `GRAFANA_ADMIN_USER` no `.env` com um usuário administrativo próprio.

O `demo-app` de referência não consome segredos por padrão; o exemplo fica comentado em `deploy/apps/demo-app/app.conf`.

```bash
sudo ./scripts/install.sh
sudoedit /opt/deploy-platform/.env
sudo chmod 600 /opt/deploy-platform/.env
```

O `install.sh` cria `/var/lib/ops-deploy` e instala o CLI. Edite `deploy/apps/<app>/app.conf` com domínio, porta e secrets reais.

## 5. Plataforma

```bash
sudo ./scripts/bootstrap-platform.sh
docker stack services platform
```

Verificação: `https://traefik.<DOMAIN>`, `https://monitor.<DOMAIN>` e `https://grafana.<DOMAIN>` respondem com TLS válido.

## 6. Runner

```bash
export RUNNER_URL="https://github.com/<org>"
export RUNNER_TOKEN="<token>"
# O script valida o SHA-256 do pacote e desabilita auto-update do runner.
sudo -E ./scripts/server/install-runner.sh
```

Verificação: job de teste consumido pelo runner. Para atualizar o runner,
altere `RUNNER_VERSION` e `RUNNER_SHA256` no script/runbook, revise a release
upstream e reinstale de forma consciente.

## 7. Aplicações

Para a aplicação piloto:

```bash
sudo -u deployer ops-deploy bootstrap <app> <versao-inicial>
```

Para as demais, o primeiro deploy pode ser feito pelo pipeline após o bootstrap. Configure monitores no Uptime Kuma e valide logs no Grafana.

## 8. Verificação final

- [ ] `ops-deploy verify <app>` saudável em todas as aplicações.
- [ ] Monitores ativos e teste de notificação entregue.
- [ ] Deploy de teste aprovado e rollback de teste executado.
- [ ] Backup de configuração criado e copiado para fora.
- [ ] `docs/acessos.md` revisado.

## Reversão

Enquanto o servidor antigo estiver disponível, a contingência é redirecionar o DNS de volta e manter o processo manual anterior. Documente a troca em `docs/estado-inicial.md`.
