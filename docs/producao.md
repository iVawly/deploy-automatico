# Prontidão para produção

Este documento separa o que está **implementado no repositório** do que só pode
ser comprovado **no host real**. Não trate a tabela como certificação: produção
exige evidência de execução e aceite.

## Status

| Área | Estado no repo | Evidência | Pendência para produção |
|---|---|---|---|
| Deploy blue-green | pronto | `ops-deploy`, testes Bats, rota file provider | executar no Swarm real |
| Rollback | pronto | `ops-deploy rollback`, runbook | drill medido com versão anterior |
| Healthcheck | pronto | `/health` profundo, smoke test no CI | validar dependência real da aplicação |
| Observabilidade | pronto | Loki/Grafana/Alloy/Uptime Kuma, monitores documentados | criar monitores e testar notificação |
| Segredos | pronto | Docker Secrets, `.env` ignorado, geração local | criar segredos reais e rotacionar |
| Supply chain | pronto | imagens por digest, actions por SHA, SBOM/proveniência, Cosign | habilitar branch protection e revisar PRs |
| Hardening de containers | pronto | read-only, cap-drop, limites | smoke test no host |
| Hardening do host | pronto | SSH, UFW, sysctl, auditd, fail2ban, daemon.json | executar e validar no Ubuntu |
| Runner | pronto | versão/checksum fixos, auto-update desligado | registrar runner e testar job |
| Backup/restore | pronto | checksum, retenção, restore seguro | restaurar em host descartável |
| CI | pronto | Gitleaks, Trivy, Hadolint, actionlint, testes, CodeQL, Scorecard | rodar no GitHub e proteger `main` |
| TLS/ACME | pronto | Traefik ACME, TLS 1.2+, headers | DNS real e emissão do certificado |
| Alertas | parcial | monitores e webhook documentados | configurar canal e testar entrega |
| HA de host | fora de escopo | ADR 0001 | aceitar risco ou evoluir arquitetura |
| Migração de dados | fora de escopo | ADR 0002 | definir estratégia por aplicação |

## Gate de go-live

Não declarar produção sem todos os itens abaixo:

- [ ] `make check` verde no commit tagueado.
- [ ] Gitleaks, Trivy, CodeQL e Scorecard verdes (ou exceções registradas).
- [ ] Branch protection em `main`: PR, review, status checks, sem force-push.
- [ ] Environment `production` com revisores.
- [ ] Servidor reconstruído pelo runbook, com SSH por chave e UFW ativo.
- [ ] Swarm com autolock; chave no cofre.
- [ ] Segredos reais criados; `GRAFANA_ADMIN_USER` e senhas fora do Git.
- [ ] Plataforma saudável: Traefik, Grafana, Loki, Alloy, Uptime Kuma,
      socket proxy.
- [ ] Aplicação piloto com deploy e rollback medidos.
- [ ] Monitores com notificação testada.
- [ ] Backup criado, copiado para fora e restaurado em ambiente descartável.
- [ ] `docs/acessos.md` e `docs/inventario.md` revisados.
- [ ] Aceite de `docs/aceite.md` assinado.

## Critérios de abortar o go-live

- Qualquer segredo real no Git ou em log.
- Imagem sem digest/SemVer ou action sem SHA em `main`.
- Healthcheck público falhando ou rollback não testado.
- Backup sem restore comprovado.
- Runner sem environment protegido ou com permissão ampla desnecessária.
- TLS inválido, dashboard exposto sem autenticação ou porta interna publicada.

## Operação contínua

- Semanal: revisar Dependabot, alertas e uso de disco.
- Mensal: revisar acessos, runners e segredos; testar restore de configuração.
- Trimestral: drill de rollback e reboot com autolock.
- Semestral: restore de volume de aplicação e revisão do threat model.
- Após incidente: atualizar runbook, threat model e ADR se o desenho mudar.
