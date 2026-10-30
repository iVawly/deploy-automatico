# Contribuindo

Obrigado por contribuir. O projeto prioriza mudanças pequenas, reversíveis,
testadas e com impacto operacional explícito.

## Ambiente

Requisitos:

- Linux ou Windows com Git Bash/WSL;
- Bash 4+, Python 3.12+, Docker (para build e stack);
- `bats-core` 1.11+, `shellcheck` 0.10+, `yamllint` 1.38+;
- opcional: `pre-commit`, `hadolint`, `actionlint`, `gitleaks`, `trivy`.

```bash
python -m unittest discover -s apps/demo-app/tests -v
make lint
make test
make lint-yaml
make lint-actions
make lint-docker
```

`make check` executa a suíte principal. `make security` roda Trivy via Docker.

## Fluxo

1. Abra uma issue ou descreva o problema no PR.
2. Crie uma branch curta (`fix/rollback-lock`, `feat/socket-proxy`).
3. Faça a menor mudança que resolve o problema.
4. Atualize testes, runbook e documentação na mesma entrega.
5. Rode `make check` e, quando aplicável, `make security`.
6. Abra o PR usando o template e preencha o impacto operacional.

## Estilo

- Shell: `bash`, `set -Eeuo pipefail`, funções pequenas, sem `eval`.
- Python: stdlib quando possível; sem dependência nova sem justificativa.
- YAML: 2 espaços, sem tabs; `yamllint` deve passar.
- Documentação em português, comandos e identificadores em inglês.
- Não adicione comentários óbvios; comente decisões e riscos.
- Não inclua segredos, tokens, chaves, domínios reais de cliente ou dados
  pessoais. Use placeholders (`<DOMAIN>`, `<token>`).

## Commits e PR

Use Conventional Commits (`fix:`, `feat:`, `docs:`, `ci:`, `chore:`). Um PR deve
ter um objetivo. Evite misturar refactor amplo com correção de comportamento.

Checklist do PR:

- [ ] Testes existentes passam; novo comportamento tem teste.
- [ ] `make check` verde.
- [ ] Nenhum segredo ou credencial real.
- [ ] Runbook/documentação atualizados.
- [ ] Impacto em produção e rollback descritos.
- [ ] Imagens/ações novas fixadas por digest/SHA.

## Adicionando uma aplicação

1. Crie `deploy/apps/<app>/app.conf` a partir do exemplo.
2. Use SemVer imutável em `APP_IMAGE_REPO:<versao>`.
3. Declare volume, segredos e caminho de saúde.
4. Mantenha `APP_READ_ONLY=1` salvo necessidade documentada.
5. Rode `ops-deploy bootstrap <app> <versao>` no primeiro deploy.
6. Adicione monitores no Uptime Kuma e valide logs no Grafana.

## Segurança

Leia `SECURITY.md` e `docs/seguranca.md`. Não abra issue pública para
vulnerabilidade. Mudanças que reduzem isolamento ou expõem porta/serviço exigem
justificativa explícita no PR e atualização do threat model.

## Licença

Ao contribuir, você concorda que sua contribuição é licenciada sob a licença MIT
do projeto.
