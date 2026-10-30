# Runbooks

Antes de operar, valide o go-live em `docs/producao.md` e o modelo de ameaças em
`docs/ameacas.md`.

Ordem sugerida de leitura para quem assume a operação:

1. [Deploy](deploy.md)
2. [Rollback](rollback.md)
3. [Alertas](alertas.md)
4. [Incidentes e diagnóstico](incidentes.md)
5. [Runner](runner.md)
6. [Recuperação e autolock](recuperacao.md)
7. [Reconstrução do servidor](reconstrucao-servidor.md)
8. [Homologação em Ubuntu 24.04](homologacao.md)

Regras:

- Comandos são executados como `deployer` (`sudo -u deployer`) para manter o ledger e as permissões corretas.
- Nunca edite `dynamic/*.yml` à mão; use `ops-deploy`.
- Toda alteração de procedimento deve atualizar o runbook na mesma entrega.
- Registre execução de deploy, rollback e incidente no canal da equipe.
