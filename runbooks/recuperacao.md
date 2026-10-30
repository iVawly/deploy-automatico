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

```bash
sudo RESTORE_FORCE=1 ./scripts/server/restore-config.sh \
  /var/backups/ops-deploy/ops-deploy-config-<stamp>.tar.gz
sudo ./scripts/install.sh
sudo ./scripts/bootstrap-platform.sh
```

O script valida o checksum, recusa caminhos absolutos/`..`, cria um backup
`pre-restore-*` e restaura `dynamic/`, `deploy/`, `runbooks/`, `docs/` e o
ledger de releases. Não inclui segredos nem volumes de dados.

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
sudo -u deployer ops-deploy rollback <app>   # garanta uma versão saudável conhecida
docker service scale app-<app>-blue=0 app-<app>-green=0
docker run --rm \
  -v demo-app-data:/data \
  -v "$PWD":/backup:ro \
  alpine sh -c 'rm -rf /data/* && tar xzf /backup/demo-app-data-<data>.tar.gz -C /data'
sudo -u deployer ops-deploy deploy <app> <versao>
```

Confirme a saúde e a integridade dos dados antes de liberar o tráfego.

## Recuperação total do host

1. Provisione um Ubuntu 24.04 limpo.
2. Siga `runbooks/reconstrucao-servidor.md`.
3. Restaure os volumes a partir do backup.
4. Revalide deploy, rollback e alertas.
5. Registre o tempo de recuperação e as lições aprendidas.

## Teste periódico

- Trimestral: restaurar um backup de configuração em servidor descartável.
- Trimestral: simular reboot com autolock e medir o tempo de desbloqueio.
- Semestral: restaurar um volume de aplicação de ensaio.
