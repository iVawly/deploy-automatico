# Runbook: recuperação e autolock

## Swarm bloqueado após reboot

O Swarm usa autolock. Após um reboot, o nó fica bloqueado até o desbloqueio com a chave guardada no cofre.

```bash
docker node ls            # deve indicar nó bloqueado
docker swarm unlock
docker node ls            # nó Ready
```

Se a chave for perdida, não é possível recuperar o estado do Swarm; siga a reconstrução em `runbooks/reconstrucao-servidor.md`.

## Serviços não sobem após o desbloqueio

```bash
docker service ls
docker service ps <servico> --no-trunc
docker stack services platform
```

Verifique: imagem disponível no GHCR, segredos existentes, redes `public`/`internal`, disco.

## Restaurar configuração

A ordem importa: instale o código, restaure a configuração (e o `.env`, se ele
foi incluído no backup) e só então faça o bootstrap. Por padrão o backup não
inclui `.env` nem segredos.

Para incluir o `.env` no backup (ele contém segredos; armazene o arquivo cifrado):

```bash
sudo env BACKUP_INCLUDE_ENV=1 /opt/deploy-platform/scripts/server/backup-config.sh
```

```bash
# 1. Se /opt/deploy-platform ainda não existe, instale a partir do clone:
sudo /caminho/do/clone/scripts/install.sh

# 2. Restaure a configuração por cima da instalação:
sudo RESTORE_FORCE=1 /opt/deploy-platform/scripts/server/restore-config.sh \
  /var/backups/ops-deploy/ops-deploy-config-<stamp>.tar.gz

# 3. Se o backup não incluiu .env, recrie (DOMAIN, ACME_EMAIL e credenciais):
sudoedit /opt/deploy-platform/.env

# 4. Recrie redes, segredos e a stack com a configuração restaurada:
sudo /opt/deploy-platform/scripts/bootstrap-platform.sh
```

O script valida o checksum pelo hash, recusa caminhos absolutos/`..`, symlinks,
hardlinks e tipos especiais, cria um backup `pre-restore-*` (incluindo o `.env`
atual, se existir) e restaura `dynamic/`, `deploy/`, `runbooks/`, `docs/`, o
ledger de releases e o `.env` quando presente no arquivo. A extração usa
`--no-same-owner`; volumes de dados continuam fora do backup.

## Restaurar dados persistentes

Backup de volume (exemplo):

```bash
docker run --rm \
  -v demo-app-data:/data:ro \
  -v "$PWD":/backup \
  alpine tar czf /backup/demo-app-data-$(date +%F).tar.gz -C /data .
```

Restauração (serviço parado):

```bash
sudo docker service scale app-<app>-blue=0 || true
sudo docker service scale app-<app>-green=0 || true
docker run --rm \
  -v demo-app-data:/data \
  -v "$PWD":/backup:ro \
  alpine sh -c 'rm -rf /data/* && tar xzf /backup/demo-app-data-<data>.tar.gz -C /data'
sudo -u deployer ops-deploy recover <app>
```

`recover` recria o slot ativo a partir do ledger restaurado, usando o digest
registrado. Se o ledger não tiver uma release ativa, faça o primeiro deploy com
`sudo -u deployer ops-deploy bootstrap <app> <versao> --digest sha256:<hash>`.
Confirme a saúde e a integridade dos dados antes de liberar o tráfego.

## Recuperação total do host

1. Provisione um Ubuntu 24.04 limpo.
2. Siga `runbooks/reconstrucao-servidor.md` até instalar Docker e o código.
3. Restaure a configuração e o `.env` antes do bootstrap da plataforma.
4. Restaure os volumes a partir do backup.
5. Revalide deploy, rollback e alertas.
6. Registre o tempo de recuperação e as lições aprendidas.

## Teste periódico

- Trimestral: restaurar um backup de configuração em servidor descartável.
- Trimestral: simular reboot com autolock e medir o tempo de desbloqueio.
- Semestral: restaurar um volume de aplicação de ensaio.
