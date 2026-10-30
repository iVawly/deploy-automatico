# Critérios de aceite e evidências

Status inicial: **pendente de execução no servidor**. Preencha data, responsável e link/print ao concluir cada item.

Procedimento de execução: [`runbooks/homologacao.md`](../runbooks/homologacao.md).

| # | Critério do cliente | Como demonstrar | Evidência | Status |
|---|---|---|---|---|
| 1 | Alteração passa por testes antes da implantação | PR com teste quebrado; pipeline para antes do build |  | pendente |
| 2 | Versão defeituosa não substitui silenciosamente a saudável | Imagem com `/health` 503; tráfego permanece no slot anterior |  | pendente |
| 3 | Aplicação que para de responder gera alerta | Parar o serviço de ensaio; alerta em até 2 min |  | pendente |
| 4 | É possível identificar a causa pelos logs | Falha simulada; causa localizada no Grafana por `app` e `version` |  | pendente |
| 5 | Recuperar versão anterior por procedimento documentado | Drill de rollback com tempo medido |  | pendente |
| 6 | Outra pessoa executa por documentação | Segundo integrante faz deploy e rollback sem ajuda |  | pendente |

## Evidências complementares

- [ ] `make check` verde no repositório de infraestrutura.
- [ ] Testes do demo-app verdes e imagem `healthy` localmente.
- [ ] Gitleaks, Trivy, CodeQL e Scorecard sem achados críticos (ou exceção registrada).
- [ ] Branch protection e environment `production` habilitados.
- [ ] Imagens da plataforma fixadas por digest; actions por SHA.
- [ ] Monitoramento ativo durante um deploy completo.
- [ ] Rollback concluído em até 5 minutos, volume preservado.
- [ ] Backup de configuração criado, checksum validado e restaurado em ambiente descartável.
- [ ] SSH por chave, UFW, fail2ban e auditd ativos no host.
- [ ] Registro da validação dos runbooks por terceiro.
- [ ] Treinamento gravado e acessível.

Checklist detalhado de go-live: `docs/producao.md`.

## Assinaturas

| Papel | Nome | Data | Aceite |
|---|---|---|---|
| Coordenador de infraestrutura |  |  |  |
| Responsável técnico |  |  |  |
