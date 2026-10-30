# Runbook: alertas

## Canais

- Painel: `https://monitor.<DOMAIN>`
- Alertas: e-mail e/ou webhook configurados no Uptime Kuma
- Logs: `https://grafana.<DOMAIN>`
- Escalonamento: `docs/ownership.md`

## Mapa de alertas

| Alerta | Significado | Primeira ação |
|---|---|---|
| `demo-app` público indisponível | URL pública não responde | `ops-deploy verify`, `docker service ps`, `runbooks/incidentes.md` |
| `demo-app` saúde não saudável | `/health` retorna 503 ou status != healthy | Ver `checks` na resposta e logs da dependência |
| Heartbeat de disco ausente | Uso de disco >= 80% ou cron falhou | `df -h`, limpar imagens/logs, `ops-deploy status` |
| Certificado TLS | Expiração próxima ou inválida | Ver logs do Traefik/ACME e DNS do domínio |
| Runner offline | Sem runner para executar deploy | `systemctl status actions.runner.*`, `runbooks/runner.md` |

## Alerta de indisponibilidade

1. Confirme no painel se é falha isolada ou persistente (2 minutos).
2. Execute:

   ```bash
   sudo -u deployer ops-deploy status <app>
   sudo -u deployer ops-deploy verify <app>
   docker service ps --filter "label=opsdeploy_app=<app>" --no-trunc
   ```

3. Se a versão ativa estiver doente e houver versão anterior saudável, avalie rollback (`runbooks/rollback.md`).
4. Se for dependência externa, siga o diagnóstico em `runbooks/incidentes.md`.
5. Confirme o encerramento: a notificação de recuperação deve chegar ao mesmo canal.

## Antiduplicação e recuperação

- O Uptime Kuma está configurado para não reenviar o mesmo alerta a cada verificação.
- A recuperação envia notificação separada.
- Não silencie o monitor sem registrar o motivo no canal da equipe.

## Teste do canal

Use **Test Notification** no Uptime Kuma. O teste não derruba nenhuma aplicação.
