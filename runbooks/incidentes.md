# Runbook: incidentes e diagnóstico

## Primeiros 5 minutos

1. Confirme o escopo: uma aplicação ou várias? (`monitor.<DOMAIN>`, `ops-deploy status`)
2. Verifique a versão ativa e a saúde:

   ```bash
   sudo -u deployer ops-deploy verify <app>
   sudo -u deployer ops-deploy status <app>
   docker service ps --filter "label=opsdeploy_app=<app>" --no-trunc
   ```

3. Abra o Grafana e filtre os logs pelo serviço e pela versão ativa.
4. Comunique o status no canal da equipe e acione o responsável conforme `docs/ownership.md`.
5. Se a falha começou após um deploy e a versão anterior estava saudável, avalie rollback.

## Onde olhar

### Saúde profunda

```bash
sudo -u deployer ops-deploy verify <app>
```

O campo `checks` indica a dependência que falhou (`status: down`) e a latência.

### Logs

Grafana → Explore → Loki:

```logql
{app="<app>"} | json | level="error"
{app="<app>", version="<versao>"} |~ "unhealthy|timeout|refused|500"
{service="<app>"} | json | duration_ms > 1000
```

### Container e serviço

```bash
docker service ps --filter "label=opsdeploy_app=<app>" --no-trunc
docker service logs --since 15m "app-<app>-<slot>"
docker service inspect "app-<app>-<slot>" --format '{{json .Spec.TaskTemplate.ContainerSpec.Image}}'
```

### Proxy e TLS

```bash
docker service logs --since 15m platform_traefik
curl -sSI https://<APP_DOMAIN>/ | head
```

### Recursos do host

```bash
df -h
free -h
docker system df
```

## Causas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `/health` 503 com `dependency: down` | banco/cache/serviço externo indisponível | Acionar dono da dependência; rollback não resolve |
| Container reiniciando | configuração inválida ou segredo ausente | `docker service ps` e `docker service logs`; corrigir config e reimplantar |
| 502/504 no proxy | nenhum slot saudável ou rota errada | Verificar rota gerada e estado dos slots |
| Certificado inválido | DNS ou ACME | Ver logs do Traefik; validar registro DNS |
| Disco cheio | imagens/logs acumulados | `docker system prune` com cuidado; validar retenção do Loki |
| Runner offline | serviço parado ou token revogado | `runbooks/runner.md` |

## Correlação de logs

Use `X-Request-ID` quando presente. Para requisições sem identificador na entrada, correlacione proxy e aplicação por serviço + janela de tempo (limitação do Traefik documentada em `docs/observabilidade.md`).

## Encerramento

1. Confirme saúde e disponibilidade.
2. Confirme notificação de recuperação no canal.
3. Registre: horário de início, detecção, causa, ação, tempo de recuperação e responsáveis.
4. Se houve rollback, anote as versões de origem e destino.
5. Abra ação de melhoria para evitar recorrência.

## Escalonamento

Siga `docs/ownership.md`. Se o incidente afetar mais de uma aplicação ou o servidor, acione o coordenador de infraestrutura imediatamente.
