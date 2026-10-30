# Observabilidade

## Endereços

- Painel de disponibilidade: `https://monitor.<DOMAIN>` (Uptime Kuma)
- Logs: `https://grafana.<DOMAIN>` (datasource Loki provisionado)
- Dashboard do Traefik: `https://traefik.<DOMAIN>` (basic auth via Docker Secret)

Substitua `<DOMAIN>` pelo valor de `DOMAIN` em `.env`.

## Monitores por aplicação

Cadastre dois monitores no Uptime Kuma para cada aplicação:

1. **Disponibilidade pública** — `HTTPS`, URL `https://<APP_DOMAIN>/`, intervalo 30s, retries 3 (alerta após ~90s), palavra-chave opcional do serviço quando conhecida.
2. **Saúde profunda** — `HTTP`, URL `http://traefik:8081/health`, cabeçalho `Host: <APP_DOMAIN>`, intervalo 30s, retries 3 (alerta após ~90s), palavra-chave `"status":"healthy"`.

A porta 8081 não é publicada no host: só containers da rede `public` alcançam o entrypoint interno de saúde.

Configuração comum:

- Notificação: e-mail e/ou webhook, com "Resend" desabilitado enquanto o serviço permanece fora.
- Notificação de recuperação habilitada.
- Descrição com link para `runbooks/alertas.md` e `runbooks/incidentes.md`.
- Tags por aplicação e criticidade.

Use **Test Notification** no canal antes de considerar a configuração concluída.

## Correlação de requisições

- Aplicações geram `X-Request-ID` quando o cliente não envia e devolvem o cabeçalho na resposta.
- O Traefik preserva `X-Request-ID` vindo do cliente nos access logs.
- Limitação: o Traefik não gera identificador. Para requisições sem o cabeçalho na entrada, correlacione proxy e aplicação por `service` + janela de tempo. Consulte a seção "Limitação conhecida" no README.

## Consultas Loki

```logql
{app="demo-app"}
{app="demo-app", version="1.4.0"} | json | level="error"
{app="demo-app"} | json | request_id="<id>"
{service="demo-app"} | json | duration_ms > 1000
{app="demo-app"} |~ "unhealthy|timeout|connection refused"
```

Filtros por rótulo: `app`, `slot`, `version`, `service`, `container`.

## Retenção e disco

- Loki: 720h (30 dias) com compactor habilitado (`deploy/logging/loki-config.yml`).
- Logs de aplicação chegam em até 30s (Alloy lê a API do Docker via `docker-socket-proxy`, sem montar o socket bruto).
- Alerta de disco: crie um monitor **Push** no Uptime Kuma e agende

  ```cron
  */5 * * * * UPTIME_KUMA_PUSH_URL=https://monitor.<DOMAIN>/api/push/<token> /opt/deploy-platform/scripts/server/disk-check.sh
  ```

  O heartbeat só é enviado abaixo de 80% de uso (`DISK_THRESHOLD` ajustável). Sem heartbeat, o Uptime Kuma alerta.

## Durante um deploy

O monitoramento é independente do ciclo de vida das aplicações: Uptime Kuma e Traefik continuam ativos enquanto um slot é substituído. O slot anterior só é reduzido após a troca de rota e a validação pública.

## Diagnóstico rápido

```bash
sudo -u deployer ops-deploy verify <app>
sudo -u deployer ops-deploy status <app>
docker service ps --filter "label=opsdeploy_app=<app>" --no-trunc
```
