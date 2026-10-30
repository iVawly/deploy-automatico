# Inventário de aplicações

Preencha uma linha por aplicação antes do onboarding. Sem dono, porta e forma de execução definidos, a aplicação não entra no pipeline.

| Aplicação | Repositório | Linguagem | Porta | Dependências obrigatórias | Dados persistentes | Criticidade | Dono | Containerizável | Observações |
|---|---|---|---|---|---|---|---|---|---|
| demo-app | exemplo/demo-app | Python 3.12 | 8080 | opcional (`DEPENDENCY_URL`) | volume `demo-app-data` em `/data` | baixa (piloto) | a definir | sim | aplicação de referência |
|  |  |  |  |  |  |  |  |  |  |

## Regras de onboarding

- Toda aplicação precisa de `Dockerfile` não root, `GET /health` profundo e logs JSON em stdout.
- Dependências obrigatórias devem falhar o `/health` com HTTP 503; dependências opcionais usam `status: skipped`.
- Segredos não vão para o repositório: documente apenas o nome do Docker Secret esperado.
- Migrações de banco seguem expand/contract e são executadas antes do deploy, nunca dentro do rollback.
