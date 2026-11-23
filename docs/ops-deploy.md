# ops-deploy

CLI em Bash para deploy blue-green em Docker Swarm de nó único. É o único ponto de operação de deploy e rollback; os runbooks chamam este CLI em vez de comandos `docker` soltos.

## Instalação

```bash
sudo ./scripts/install.sh
```

Instala em `/opt/deploy-platform`, cria `/var/lib/ops-deploy` e `/var/log/ops-deploy` (donos `deployer`) e o link `/usr/local/bin/ops-deploy` para o CLI instalado. A configuração de cada aplicação fica em `deploy/apps/<app>/app.conf`.

## Subcomandos

```bash
ops-deploy bootstrap <app> <versao> --digest sha256:<hash>
ops-deploy deploy <app> <versao> --digest sha256:<hash>
ops-deploy rollback <app> [versao]
ops-deploy recover <app> [--from-ledger]
ops-deploy verify <app> [--slot blue|green] [--quiet]
ops-deploy status <app> [--json]
ops-deploy doctor <app> [--json]
ops-deploy reconcile <app> --accept-route|--accept-ledger
```

`deploy` e `bootstrap` exigem digest; `OPS_DEPLOY_IMAGE_DIGEST` pode substituir
`--digest`. `OPS_DEPLOY_ALLOW_MUTABLE_TAG=1` libera tag sem digest em
deploy/bootstrap/recover/rollback apenas para demo local e migração legada.
A versão precisa ser SemVer utilizável como tag Docker; build metadata (`+...`)
não é aceito.

`verify --quiet` imprime a linha resumida em vez do JSON.

### Modelo de estado

- **Rota** (`dynamic/<app>.yml`) é o estado **desejado/configurado**. O Traefik
  aplica o arquivo de forma assíncrona; a rota sozinha não prova que a versão
  esperada já está sendo servida.
- **Ledger** (`/var/lib/ops-deploy/releases.jsonl`) é o **histórico/auditoria**
  append-only. Um registro final incompleto é descartado antes do próximo
  append.
- **Runtime** é o estado dos serviços Docker; **observado** é a sonda pública e
  de saúde interna. `doctor` consulta o runtime e a sonda pública; a saúde
  interna é validada por `deploy`, `bootstrap`, `recover`, `rollback` e
  `verify`. `deploy` e `rollback` recusam quando rota e ledger divergem e quando
  o tráfego público ainda não confirma a versão desejada (aplicação pendente do
  Traefik). `deploy` também exige o slot ativo saudável; `rollback` pode partir
  de uma versão atual doente, mas exige saúde do alvo antes da troca.
- Se não houver sonda **pública** que confirme versão (`APP_VERIFY_PUBLIC=0` ou
  `APP_PUBLIC_EXPECT_VERSION=0`), o estado é **não verificado** e `deploy`/
  `rollback` são recusados, salvo `OPS_DEPLOY_ALLOW_UNVERIFIED=1` explícito.
  `APP_HEALTH_EXPECT_VERSION=1` adiciona conferência de versão no `/health`, mas
  não substitui a sonda pública.

Use `doctor` para diagnosticar e `reconcile` para escolher explicitamente qual
lado é a verdade; não há correção automática por adivinhação.

### bootstrap

Primeira instalação. Sobe o slot `blue`, aguarda saúde (e a versão, quando
`APP_HEALTH_EXPECT_VERSION=1`), publica a rota, valida o hostname público quando
`APP_VERIFY_PUBLIC=1` (incluindo a versão com `APP_PUBLIC_EXPECT_VERSION=1`) e
grava a release inicial. Recusa se já existir release estável **ou** qualquer
arquivo de rota para a aplicação, inclusive fora do formato gerado pelo CLI.

```bash
sudo -u deployer ops-deploy bootstrap demo-app 1.0.0 --digest sha256:<hash>
```

### deploy

1. Exige sonda pública que confirme versão, salvo `OPS_DEPLOY_ALLOW_UNVERIFIED=1` (com aviso).
2. Exige consistência entre rota desejada e ledger; divergência bloqueia o deploy.
3. Com `APP_VERIFY_PUBLIC=1`, confirma que o tráfego público já serve a versão ativa (aplicação do Traefik concluída).
4. Verifica a saúde do slot ativo (pré-condição).
5. Baixa a imagem imutável `APP_IMAGE_REPO:<versao>@sha256:<hash>`.
6. Recria o slot inativo com a configuração atual e aguarda o healthcheck profundo.
7. Troca a rota do Traefik de forma atômica e valida o hostname público (quando `APP_VERIFY_PUBLIC=1`).
8. Registra a release, incluindo o digest, e reduz o slot anterior a zero após `OPS_DEPLOY_DRAIN_SECONDS`, salvo `APP_KEEP_PREVIOUS=1`.

Qualquer falha antes da troca mantém o tráfego no slot ativo. Com `APP_VERIFY_PUBLIC=1`, falha na validação pública restaura a rota anterior. Se a rota foi aplicada mas o registro no ledger falhar, o comando alerta e instrui `reconcile --accept-route`; não há reversão automática.

```bash
sudo -u deployer ops-deploy deploy demo-app 1.4.0 --digest sha256:<hash>
```

### rollback

Sem argumento de versão, escolhe a última release estável diferente da atual. Com versão, exige que ela conste no histórico como estável. O volume persistente nunca é removido ou recriado.

```bash
sudo -u deployer ops-deploy rollback demo-app
sudo -u deployer ops-deploy rollback demo-app 1.3.2
```

Falha de saúde **antes** da troca preserva a versão atual. Falha de validação pública **depois** da troca mantém a versão restaurada para diagnóstico e envia alerta crítico quando `OPS_DEPLOY_ALERT_WEBHOOK` está definido.

### recover

Recria o slot **desejado** (cabeçalho da rota) usando o digest da rota. Se a
rota não tiver digest e apontar para a mesma versão/slot do ledger, herda o
digest do ledger; em caso de divergência rota ↔ ledger ou quando nenhum dos dois
tem digest, não herda e exige `OPS_DEPLOY_ALLOW_MUTABLE_TAG=1` para recuperar
por tag. Se a rota não existir ou não estiver no formato gerado pelo CLI, o
comando recusa e exige `--from-ledger` para escolher explicitamente a última
release estável do ledger.

```bash
sudo -u deployer ops-deploy recover demo-app
sudo -u deployer ops-deploy recover demo-app --from-ledger
```

Falha de saúde ou de validação pública aborta antes de considerar a recuperação
concluída. Se o serviço subir mas o ledger não puder ser gravado, o comando
alerta e instrui `reconcile --accept-route`.

### verify

Consulta `http://app-<app>-<slot>:<porta><health_path>` com timeout
`APP_HEALTH_TIMEOUT` (padrão de 5 segundos) e imprime JSON:

```json
{"app":"demo-app","slot":"green","expected_version":"1.4.0","healthy":true,"http_code":"200","checked_at":"...","body":"{\"status\":\"healthy\",\"version\":\"1.4.0\"}"}
```

Código de saída 0 somente quando o corpo indica `"status":"healthy"` e, com
`APP_HEALTH_EXPECT_VERSION=1`, a `"version"` do corpo é igual à versão esperada
(rota desejada ou ledger).

### status

Mostra versão/slot ativos, as últimas versões estáveis (`APP_KEEP_VERSIONS`,
padrão 5, com data de implantação e saúde registrada), as últimas releases e o
estado dos serviços.

```bash
sudo -u deployer ops-deploy status demo-app
sudo -u deployer ops-deploy status demo-app --json
```

O JSON inclui `active_digest`, `retention_limit` e `stable_versions`, cada uma
com `version`, `slot`, `digest`, `deployed_at` e `healthy` (saúde registrada no
deploy, não uma sonda ao vivo). Também inclui `desired_version`, `desired_slot`,
`desired_digest`, `consistent`, `version_probe` (`enabled`/`unverified`),
`last_action` e `last_result`.

```json
{"app":"demo-app","active_version":"1.4.0","active_slot":"green","active_digest":"sha256:...","since":"...","retention_limit":5,"desired_version":"1.4.0","desired_slot":"green","desired_digest":"sha256:...","consistent":true,"version_probe":"enabled","last_action":"deploy","last_result":"success","stable_versions":[{"version":"1.4.0","slot":"green","digest":"sha256:...","deployed_at":"...","healthy":true}]}
```

### doctor

Somente leitura. Compara estado desejado (rota), ledger, runtime Docker e sonda
pública observada. Não executa healthcheck interno; para isso use `verify`. Sem
o binário `docker`, o runtime fica `unknown`, a sonda pública via container não é
executada e o comando sai com `2`. Códigos de saída: `0` consistente, `1`
inseguro/divergente (inclui `apply-pending` e `runtime-mismatch`), `2` não
verificado ou precisa de reconciliação (`route-missing`, `route-invalid`,
`ledger-drift`, `unverified`, `runtime-unknown`).

```bash
sudo -u deployer ops-deploy doctor demo-app
sudo -u deployer ops-deploy doctor demo-app --json
```

### reconcile

Repara a divergência escolhendo explicitamente um lado e registra a decisão no
ledger:

- `--accept-route`: grava a rota desejada como release estável (quando a rota é
  a verdade, por exemplo após um rollback que falhou na validação pública).
- `--accept-ledger`: reescreve a rota a partir da última release estável do
  ledger.

```bash
sudo -u deployer ops-deploy reconcile demo-app --accept-route
sudo -u deployer ops-deploy reconcile demo-app --accept-ledger
```

## app.conf

| Variável | Obrigatória | Descrição |
|---|---|---|
| `APP_NAME` | sim | Deve coincidir com o diretório |
| `APP_DOMAIN` | sim | Hostname público roteado pelo Traefik |
| `APP_PORT` | sim | Porta HTTP do container |
| `APP_IMAGE_REPO` | sim | Repositório da imagem no GHCR |
| `APP_HEALTH_PATH` | não | Padrão `/health` |
| `APP_VOLUME` | não | Volume Docker preservado entre releases |
| `APP_MOUNT_PATH` | não | Padrão `/data` |
| `APP_SECRETS` | não | Nomes de Docker Secrets a montar; nomes e existência são validados antes de qualquer alteração no serviço |
| `APP_NETWORK` | não | Padrão `public`; a rede precisa existir antes de qualquer alteração no serviço |
| `APP_PROBE_IMAGE` | não | Imagem com `curl` usada nas sondas via Docker (padrão fixado por digest) |
| `APP_HEALTH_TIMEOUT` | não | Padrão 5 segundos |
| `APP_HEALTH_RETRIES` | não | Padrão 12 tentativas |
| `APP_HEALTH_INTERVAL` | não | Padrão 5 segundos |
| `APP_PUBLIC_CHECK_PATH` | não | Caminho validado após a troca (padrão `/`) |
| `APP_VERIFY_PUBLIC` | não | `1` para validar via Traefik |
| `APP_PUBLIC_EXPECT_VERSION` | não | `1` exige que a sonda pública exponha `"version"` igual à versão implantada (padrão `0`) |
| `APP_HEALTH_EXPECT_VERSION` | não | `1` exige que `/health` exponha `"version"` igual à versão implantada (padrão `0`) |
| `APP_KEEP_PREVIOUS` | não | `1` mantém o slot anterior em execução |
| `APP_KEEP_VERSIONS` | não | Versões estáveis exibidas no `status` (padrão `5`); o ledger não é podado |
| `APP_READ_ONLY` | não | `1` monta o rootfs read-only (padrão) |
| `APP_MEMORY_LIMIT` | não | Limite de memória (padrão `256M`) |
| `APP_CPU_LIMIT` | não | Limite de CPU (padrão `0.50`) |
| `APP_PIDS_LIMIT` | não | Limite de PIDs (padrão `128`) |
| `APP_TMPFS_SIZE` | não | Bytes de `/tmp` (padrão `16777216`) |
| `APP_STOP_GRACE_PERIOD` | não | Tempo de drenagem no stop (padrão `30s`) |
| `APP_LOG_MAX_SIZE` | não | Rotação do log Docker (padrão `10m`) |
| `APP_LOG_MAX_FILE` | não | Arquivos de log mantidos (padrão `3`) |
| `APP_CAP_DROP` | não | Capacidades removidas (padrão `ALL`) |

Tamanhos (`APP_MEMORY_LIMIT`, `APP_LOG_MAX_SIZE`) aceitam bytes ou sufixos
`k/m/g/t/p` (decimal e espaço opcionais, ex.: `256M`, `10.5m`); CPU é decimal
(`0` permitido); duração aceita compostos como `1m30s` e `0`. Valor inválido
falha em `load_app` antes de remover ou recriar qualquer serviço.

## Hardening do serviço

Cada slot é criado com rootfs read-only, todas as
capabilities removidas, `/tmp` em tmpfs, limites de
CPU/memória/PIDs, `init` como PID 1, `stop-grace-period` e rotação de logs. O CLI aplica
`no-new-privileges` quando o Docker suporta a flag; caso contrário, avisa e
mantém os demais controles. A aplicação deve
gravar apenas no volume montado em `APP_MOUNT_PATH` (padrão `/data`). Se a
imagem precisar de rootfs gravável, defina `APP_READ_ONLY=0` de forma
consciente e documente o motivo no PR.

## Variáveis de ambiente do CLI

| Variável | Padrão | Uso |
|---|---|---|
| `OPS_DEPLOY_ROOT` | pai de `scripts/` | Raiz do repositório instalado |
| `OPS_DEPLOY_APPS_DIR` | `<root>/deploy/apps` | Diretório com `<app>/app.conf` |
| `OPS_DEPLOY_STATE_DIR` | `/var/lib/ops-deploy` | Ledger `releases.jsonl` e lock |
| `OPS_DEPLOY_DYNAMIC_DIR` | `<root>/dynamic` | Rotas do Traefik |
| `OPS_DEPLOY_PROBE_MODE` | `docker` | `local` usa curl do host (testes) |
| `OPS_DEPLOY_PROXY_HOST` | `platform_traefik` | DNS do proxy na rede overlay |
| `OPS_DEPLOY_CERT_RESOLVER` | `letsencrypt` | Resolver ACME da rota; vazio usa o certificado padrão |
| `OPS_DEPLOY_INSECURE_TLS` | `0` | `1` ignora a verificação TLS na sonda pública (demo local) |
| `OPS_DEPLOY_DRY_RUN` | `0` | Preview: descreve ações sem mutar serviços, rotas, lock ou ledger |
| `OPS_DEPLOY_PUBLIC_RETRIES` | `6` | Tentativas da sonda pública |
| `OPS_DEPLOY_PUBLIC_INTERVAL` | `2` | Segundos entre tentativas da sonda pública |
| `OPS_DEPLOY_RETRY_MAX` | `3` | Tentativas para comandos Docker transitórios |
| `OPS_DEPLOY_RETRY_DELAY` | `2` | Segundos entre tentativas |
| `OPS_DEPLOY_DRAIN_SECONDS` | `10` | Janela antes de reduzir o slot anterior |
| `OPS_DEPLOY_ALERT_WEBHOOK` | vazio | Alerta crítico em falha de rollback e em mutação aplicada sem registro no ledger |
| `OPS_DEPLOY_ACTOR` | `GITHUB_ACTOR`/`id -un` | Autor no ledger |
| `OPS_DEPLOY_COMMIT` | `GITHUB_SHA` | Commit no ledger |
| `OPS_DEPLOY_IMAGE_DIGEST` | vazio | Digest usado por `deploy`/`bootstrap` |
| `OPS_DEPLOY_ALLOW_MUTABLE_TAG` | `0` | `1` libera tag sem digest em deploy/bootstrap/recover/rollback (legado/demo) |
| `OPS_DEPLOY_ALLOW_UNVERIFIED` | `0` | `1` aceita deploy/rollback sem sonda pública que confirme versão (com aviso explícito) |

## Histórico

`/var/lib/ops-deploy/releases.jsonl`, uma linha JSON por evento:

```json
{"ts":"...","app":"demo-app","version":"1.4.0","commit":"...","slot":"green","action":"deploy","result":"success","author":"ci","checksum":"...","digest":"sha256:...","message":"promovido para green"}
```

O ledger é append-only e representa histórico, não o estado servido. Antes de
cada escrita, um eventual registro final incompleto (sem newline) é reparado ou
descartado sob o lock. `action=reconcile` registra uma decisão explícita de
`reconcile`; como o resultado é `success`, o registro passa a ser a última
release estável considerada por `status`, `deploy` e `rollback`. Em
`--accept-ledger` a versão/slot é a mesma do ledger; em `--accept-route` ela vem
da rota desejada.

## Testes

```bash
make lint
make test
```

Os testes usam dublês de `docker` e `curl` em `tests/shims/`, exercitando promoção, pré-condições, reprovação por saúde, restauração de rota, rollback, versão/digest imutável e preservação de volume.
