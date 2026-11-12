# Histórico de auditoria

Nenhuma pendência aberta. Este arquivo registra as correções concluídas nas
rodadas de auditoria.

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
  `--security-opt no-new-privileges:true` quando o Docker suporta;
  `docs/seguranca.md` e
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
  (restaura rota, sem webhook) e falha de rollback após a troca (webhook
  crítico quando configurado).
- [x] **M11 — Demo local frágil.** `openssl passwd -apr1 -stdin` sem newline,
  timeout do Traefik falha explicitamente e `demo.sh` valida cada `verify` com
  mensagem de contexto.
- [x] **M12 — OpenSpec desatualizado.** `promote` removido do desenho; a
  listagem no ledger foi concluída e a retenção no GHCR ficou como pendência
  explícita.
- [x] **M13 — Backup/restore não cobrem `.env`.** `BACKUP_INCLUDE_ENV=1` inclui o
  `.env`; restore o aplica com `0600` e preserva backup `pre-restore`.
- [x] **M14 — Logs do pipeline não centralizados.** `scripts/ci/log-exec.sh`
  grava JSONL em `/var/log/ops-deploy/pipeline.jsonl`; Alloy coleta o diretório e
  envia ao Loki com `app="pipeline"`. Workflow usa o wrapper em deploy/verify.
- [x] **M15 — Demo local validava o proxy errado.** O wrapper usava o padrão
  `platform_traefik`, mas a stack local é `demo-platform`, cujo DNS é
  `demo-platform_traefik`; o `bootstrap`/`deploy` abortava na verificação
  pública. `local-demo/scripts/ops` agora deriva `OPS_DEPLOY_PROXY_HOST` de
  `DEMO_STACK`, alinhado ao README e a `docs/observabilidade.md`.
- [x] **M16 — `OPS_DEPLOY_DRY_RUN` não era um preview seguro.** Em modo docker as
  sondas falhavam porque nenhum serviço era criado, o ledger recebia eventos
  `failed` e a escrita de rota não era protegida. O dry-run agora ignora sondas
  e esperas, não grava rota/ledger, não adquire lock e apenas descreve as ações.
- [x] **M17 — Retry de `docker service create` não era idempotente.** Se o
  primeiro create concluísse no servidor mas retornasse erro transitório, as
  tentativas seguintes falhavam com "name already in use" e o deploy era
  abortado. `create_service_retry` detecta o serviço criado (quando ele estava
  ausente antes) e segue para o health check, sem aceitar serviço pré-existente
  de uma remoção incompleta.
- [x] **M18 — `app.conf` podia desligar proteções silenciosamente.** Valores
  inválidos em `APP_READ_ONLY` (`true` em vez de `1`) deixavam o rootfs
  gravável, e `APP_PIDS_LIMIT` não numérico removia o limite de PIDs sem aviso.
  `load_app` agora valida porta, timeouts, retries, tmpfs, logs, PIDs e flags
  0/1, falhando cedo com mensagem clara.
- [x] **M19 — `install-docker.sh` sobrescrevia `daemon.json`.** O arquivo
  existente era apenas copiado como backup e substituído, perdendo
  `data-root`, `registry-mirrors` e outras chaves locais. Agora as chaves
  gerenciadas são mescladas via `python3`, preservando o restante; JSON inválido
  ou ausência de `python3` aborta antes de alterar o arquivo.
- [x] **M20 — `X-Request-ID` refletido sem validação.** O demo-app copiava o
  cabeçalho recebido para a resposta; um valor com CRLF/obs-fold injetava
  continuação de cabeçalho. `request_id` aceita apenas
  `[A-Za-z0-9._:-]` com até 128 caracteres e gera UUID quando o valor é
  inseguro; testes cobrem CRLF, excesso de tamanho e espaços.
- [x] **M21 — `APP_SECRETS` validado após a remoção do serviço.** O
  `deploy_slot` removia o serviço antes de validar os nomes; um segredo
  inválido podia derrubar o slot ativo no `recover` ou o slot anterior no
  `deploy` e só então abortar. A validação foi movida para `load_app`, antes de
  qualquer mutação, e o regex agora exige primeiro caractere alfanumérico;
  teste cobre `recover` sem remover o serviço.
- [x] **M22 — Restore aceitava symlink/hardlink no tar.** A checagem bloqueava
  caminhos absolutos e `..`, mas não entradas `l`/`h`/especiais. Um backup com
  `dynamic -> /etc` podia ser preservado por `cp -a` e fazer o bootstrap
  escrever como root fora de `DEST`. O restore agora recusa symlink, hardlink e
  tipos especiais, extrai com `--no-same-owner` e valida o arquivo em modo de
  simulação; testes cobrem symlink e hardlink.

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
- [x] **B14 — Checagem de permissão do `.env` incompleta.** O padrão
  `*[1-7][0-7]` não detectava modos como `604`/`601`. `bootstrap-platform.sh`
  agora verifica os dois últimos dígitos octais e alerta qualquer modo cujo
  grupo/outros não seja `00`.
- [x] **B15 — `HEALTHCHECK` fixava a porta 8080.** O Dockerfile ignorava
  `APP_PORT`, marcando como unhealthy apps configurados em outra porta. O
  healthcheck lê `APP_PORT` (padrão `8080`).
- [x] **B16 — `APP_SECRETS` sujeito a glob e nomes inválidos.** O valor era
  expandido pelo shell em `--secret source=...`. Agora é lido como array sem
  glob e cada nome precisa casar `^[A-Za-z0-9_.-]+$`, falhando cedo caso
  contrário.
- [x] **B17 — CI não rodava shellcheck em `scripts/ci/*.sh`.** O `Makefile`
  cobria esses arquivos, mas o workflow não; a lista do CI foi alinhada.
- [x] **B18 — Retry inválido caía no default silenciosamente.**
  `OPS_DEPLOY_RETRY_MAX`/`OPS_DEPLOY_RETRY_DELAY` não numéricos eram ignorados.
  Ambos são validados no início do CLI, com erro explícito.
- [x] **B19 — `make lint-yaml` falhava no demo local.** O fim de
  `local-demo/docker-compose.yml` tinha espaços em branco e nenhum newline
  final, quebrando o job de YAML do CI. O arquivo foi normalizado.
- [x] **B20 — Dry-run aguardava a drenagem.** Mesmo sem criar serviço, o
  `deploy`/`rollback` simulados executavam `sleep "$DRAIN_SECONDS"`. O bloco de
  drenagem agora é ignorado no dry-run; teste usa `timeout` para garantir que
  não há espera.
- [x] **B21 — `recover`/`rollback` ignoravam argumentos extras.** Comandos como
  `rollback app 1.0.0 --digest ...` aceitavam o argumento extra e podiam induzir
  o operador a achar que ele foi aplicado. Ambos rejeitam argumentos além dos
  previstos; testes cobrem.
- [x] **B22 — `APP_KEEP_VERSIONS` com zero à esquerda.** `08` era interpretado
  como octal e rejeitado; agora a validação usa base decimal e normaliza o
  valor antes de expô-lo no JSON do `status`.

## Histórico

- 2026-09-11: arquivo criado a partir da verificação do commit `18f84b1`.
- 2026-10-11: altos, médios e baixos resolvidos e validados com `shellcheck`,
  `bash -n`, `bats` (22 testes), `python3 -m unittest` (7 testes) e `yamllint`.
- 2026-11-11: segunda rodada de auditoria (M15–M20, B14–B19) corrigida e validada
  com `shellcheck`, `bash -n`, `bats` (32 testes) e `python3 -m unittest`
  (10 testes).
- 2026-11-11: rodada final (M21–M22, B20–B22) corrigida e validada com
  `shellcheck`, `bash -n`, `bats` (40 testes), `docker compose config` e
  `python3 -m unittest` (10 testes). Auditoria ampla encerrada; próximos ajustes
  somente mediante falha concreta ou mudança de requisito.
