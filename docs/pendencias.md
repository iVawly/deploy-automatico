# Pendências de auditoria

Escopo desta rodada: os **5 altos**, os **14 médios** e os **13 baixos**
levantados na revisão atual.

Legenda: `[x]` resolvido (com validação)

## Altos

- [x] **H1 — DNS curto no Swarm.** `traefik`, `grafana` e `uptime-kuma` usados
  como hostname em `scripts/ops-deploy`, `deploy/traefik/dynamic/platform.yml.tpl`,
  `local-demo/dynamic/platform.yml` e `docs/observabilidade.md`. Corrigido com
  nomes qualificados pela stack (`platform_*`), renderização do template local e
  `OPS_DEPLOY_PROXY_HOST` configurável no CLI.
- [x] **H2 — `verify` gera JSON inválido.** `json_escape` agora cobre controle,
  CR, tab e newline; o corpo é emitido como string JSON válida. Teste bats cobre
  resposta não-JSON.
- [x] **H3 — Segredos com newline.** Bootstrap, docs e runbook usam `printf '%s'`
  antes de `docker secret create`, sem `\n` no valor.
- [x] **H4 — Demo local preso ao Git Bash.** `cygpath` passou a ser opcional;
  WSL/Linux usa o caminho nativo e o README reflete isso.
- [x] **H5 — Sem retry/backoff em `docker service create`/`pull`.** `run_cmd_retry`
  com `OPS_DEPLOY_RETRY_MAX`/`OPS_DEPLOY_RETRY_DELAY` cobre pull, create,
  bootstrap, deploy, rollback e recover.

## Médios

- [x] **M1 — `no-new-privileges` ausente e doc incorreta.** Slots usam
  `--security-opt no-new-privileges:true`; `docs/seguranca.md` e
  `docs/ops-deploy.md` corrigidos.
- [x] **M2 — Corrida no `deploy_slot`.** Após `service rm`, o CLI aguarda o
  serviço sumir (`wait_service_absent`) antes de recriar, com retry no create.
- [x] **M3 — `.env.example` não é plug-and-play.** Bootstrap cria
  `traefik_dashboard_users` e `grafana_admin_password` a partir do `.env` e
  falha com mensagem clara quando faltam valores.
- [x] **M4 — Placeholder de imagem da aplicação.** `APP_IMAGE_REPO` aponta para
  `ghcr.io/ivawly/deploy-automatico/demo-app`; forks ajustam apenas o owner.
- [x] **M5 — Firewall sem portas de Swarm.** `firewall.sh` libera 2377/tcp,
  7946/tcp+udp e 4789/udp restritos a `SWARM_CIDR` (vazio em nó único); docs e
  runbook atualizados.
- [x] **M6 — Ajustes globais do Docker.** `DOCKER_ADDRESS_POOL`,
  `DOCKER_ADDRESS_POOL_SIZE`, `DOCKER_ICC` e `DOCKER_USERLAND_PROXY` permitem
  sobrescrever os padrões sem editar o script; validação e documentação incluídas.
- [x] **M7 — `make test`/CONTRIBUTING usam `python`.** Makefile, CI e
  CONTRIBUTING usam `python3`.
- [x] **M8 — Cloud-init sem pin de commit.** Clone usa `--no-checkout` e
  `checkout --detach REPLACE_WITH_COMMIT_SHA`; runbook mostra como preencher.
- [x] **M9 — Label de log errado na doc.** Consulta e descrição dos filtros usam
  `app` para a aplicação lógica e explicam que `service` é o nome real do
  serviço Swarm (`app-<app>-<slot>`).
- [x] **M10 — Doc superestima rollback/alerta.** Tabela de falhas distingue
  falha antes da troca (sem rollback e sem webhook), falha pública após a troca
  (restaura rota, sem webhook) e falha de rollback após a troca (webhook crítico).
- [x] **M11 — Demo local frágil.** `openssl passwd -apr1 -stdin` sem newline,
  timeout do Traefik falha explicitamente e `demo.sh` valida cada `verify` com
  mensagem de contexto.
- [x] **M12 — OpenSpec desatualizado.** `promote` removido do desenho; task de
  retenção foi separada entre ledger (concluída) e GHCR (pendente explícita).
- [x] **M13 — Backup/restore não cobrem `.env`.** `BACKUP_INCLUDE_ENV=1` inclui o
  `.env`; restore o aplica com `0600` e preserva backup `pre-restore`.
- [x] **M14 — Logs do pipeline não centralizados.** `scripts/ci/log-exec.sh`
  grava JSONL em `/var/log/ops-deploy/pipeline.jsonl`; Alloy coleta o diretório e
  envia ao Loki com `app="pipeline"`. Workflow usa o wrapper em deploy/verify.

## Baixos

- [x] **B1 — Interpolação de `inputs.version` no shell.** Workflows monorepo e
  standalone usam `env: INPUT_VERSION` e `$GITHUB_EVENT_NAME`; entrada do usuário
  não é mais expandida diretamente no script.
- [x] **B2 — `bootstrap`/`recover` ignoravam `APP_VERIFY_PUBLIC`.** Ambos só
  validam o hostname público quando a flag é `1`, como `deploy`/`rollback`.
- [x] **B3 — Falha de `deploy_slot` no bootstrap sem ledger.** Agora registra
  `bootstrap failed` com a mensagem de criação do serviço inicial.
- [x] **B4 — Argumentos de `verify`/`status` sem validação.** `--slot` exige
  valor e `status` rejeita argumentos desconhecidos.
- [x] **B5 — Env numéricas sem validação.** `OPS_DEPLOY_PUBLIC_RETRIES`,
  `OPS_DEPLOY_PUBLIC_INTERVAL` e `OPS_DEPLOY_DRAIN_SECONDS` falham cedo com
  mensagem clara.
- [x] **B6 — `DISK_THRESHOLD` sem validação.** `disk-check.sh` aceita apenas
  inteiro de 1 a 100.
- [x] **B7 — `down.sh` sem validação.** Confere `DEMO_STACK` e a presença do
  Docker antes de remover a stack.
- [x] **B8 — Demo não falhava se o deploy reprovado passasse.** `demo.sh` exige
  exit code 1 no cenário de dependência quebrada.
- [x] **B9 — `up.sh` sem timeout e sem checar `openssl`.** `curl` usa
  `--max-time 5` e o script valida `docker`, `curl` e `openssl` no início.
- [x] **B10 — `apt-get install` sem `--no-install-recommends`.** Aplicado em
  `harden-system.sh` e `firewall.sh`.
- [x] **B11 — Documentação desatualizada.** Índice inclui pendências; instalação
  cita `/var/log/ops-deploy`; arquitetura cita logs do pipeline; observabilidade
  cita a stack local; `healthy` do `status` é explicitamente histórico; changelog
  alinhado ao CLI 1.2.0.
- [x] **B12 — Workflow standalone usava `python` e interpolação direta.** Passou
  a usar `python3`, `PYTHONPATH=.` e `INPUT_VERSION` via `env`.
- [x] **B13 — Renderização e repo Docker frágeis.** `up.sh` escapa `&`, `\` e
  `|` antes do `sed`; `install-docker.sh` valida `VERSION_CODENAME` e usa
  `--no-install-recommends`.

## Histórico

- 2026-11-09: arquivo criado a partir da verificação do commit `18f84b1`.
- 2026-11-10: altos, médios e baixos resolvidos e validados com `shellcheck`,
  `bash -n`, `bats` (22 testes), `python3 -m unittest` (7 testes) e `yamllint`.
