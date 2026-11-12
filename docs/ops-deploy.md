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
ops-deploy recover <app>
ops-deploy verify <app> [--slot blue|green] [--quiet]
ops-deploy status <app> [--json]
```

`deploy` e `bootstrap` exigem digest; `OPS_DEPLOY_IMAGE_DIGEST` pode substituir
`--digest`. `OPS_DEPLOY_ALLOW_MUTABLE_TAG=1` libera tag sem digest apenas para
demo local e migração legada.

`verify --quiet` imprime a linha resumida em vez do JSON.

### bootstrap

Primeira instalação. Sobe o slot `blue`, aguarda saúde, publica a rota e grava a release inicial. Recusa se já existir release estável.

```bash
sudo -u deployer ops-deploy bootstrap demo-app 1.0.0 --digest sha256:<hash>
```

### deploy

1. Verifica a saúde do slot ativo (pré-condição).
2. Baixa a imagem imutável `APP_IMAGE_REPO:<versao>@sha256:<hash>`.
3. Recria o slot inativo com a configuração atual e aguarda o healthcheck profundo.
4. Troca a rota do Traefik de forma atômica e valida o hostname público (quando `APP_VERIFY_PUBLIC=1`).
5. Registra a release, incluindo o digest, e reduz o slot anterior a zero após `OPS_DEPLOY_DRAIN_SECONDS`, salvo `APP_KEEP_PREVIOUS=1`.

Qualquer falha antes da troca mantém o tráfego no slot ativo. Com `APP_VERIFY_PUBLIC=1`, falha na validação pública restaura a rota anterior.

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

Recria o slot ativo a partir da última release bem-sucedida do ledger, usando o
digest registrado. Não altera versão nem escolhe outro slot.

```bash
sudo -u deployer ops-deploy recover demo-app
```

### verify

Consulta `http://app-<app>-<slot>:<porta><health_path>` com timeout de 5 segundos e imprime JSON:

```json
{"app":"demo-app","slot":"green","healthy":true,"http_code":"200","checked_at":"...","body":{...}}
```

Código de saída 0 somente quando o corpo indica `"status":"healthy"`.

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
deploy, não uma sonda ao vivo):

```json
{"app":"demo-app","active_version":"1.4.0","active_slot":"green","active_digest":"sha256:...","since":"...","retention_limit":5,"stable_versions":[{"version":"1.4.0","slot":"green","digest":"sha256:...","deployed_at":"...","healthy":true}]}
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
| `APP_SECRETS` | não | Nomes de Docker Secrets a montar; validados antes de qualquer alteração no serviço |
| `APP_NETWORK` | não | Padrão `public` |
| `APP_HEALTH_TIMEOUT` | não | Padrão 5 segundos |
| `APP_HEALTH_RETRIES` | não | Padrão 12 tentativas |
| `APP_HEALTH_INTERVAL` | não | Padrão 5 segundos |
| `APP_PUBLIC_CHECK_PATH` | não | Caminho validado após a troca (padrão `/`) |
| `APP_VERIFY_PUBLIC` | não | `1` para validar via Traefik |
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
| `OPS_DEPLOY_STATE_DIR` | `/var/lib/ops-deploy` | Ledger `releases.jsonl` e lock |
| `OPS_DEPLOY_DYNAMIC_DIR` | `<root>/dynamic` | Rotas do Traefik |
| `OPS_DEPLOY_PROBE_MODE` | `docker` | `local` usa curl do host (testes) |
| `OPS_DEPLOY_PROXY_HOST` | `platform_traefik` | DNS do proxy na rede overlay |
| `OPS_DEPLOY_DRY_RUN` | `0` | Preview: descreve ações sem mutar serviços, rotas, lock ou ledger |
| `OPS_DEPLOY_RETRY_MAX` | `3` | Tentativas para comandos Docker transitórios |
| `OPS_DEPLOY_RETRY_DELAY` | `2` | Segundos entre tentativas |
| `OPS_DEPLOY_DRAIN_SECONDS` | `10` | Janela antes de reduzir o slot anterior |
| `OPS_DEPLOY_ALERT_WEBHOOK` | vazio | Alerta crítico em falha de rollback |
| `OPS_DEPLOY_ACTOR` | `GITHUB_ACTOR`/`id -un` | Autor no ledger |
| `OPS_DEPLOY_COMMIT` | `GITHUB_SHA` | Commit no ledger |
| `OPS_DEPLOY_IMAGE_DIGEST` | vazio | Digest usado por `deploy`/`bootstrap` |
| `OPS_DEPLOY_ALLOW_MUTABLE_TAG` | `0` | `1` libera tag sem digest (legado/demo) |

## Histórico

`/var/lib/ops-deploy/releases.jsonl`, uma linha JSON por evento:

```json
{"ts":"...","app":"demo-app","version":"1.4.0","commit":"...","slot":"green","action":"deploy","result":"success","author":"ci","checksum":"...","digest":"sha256:...","message":"promovido para green"}
```

## Testes

```bash
make lint
make test
```

Os testes usam dublês de `docker` e `curl` em `tests/shims/`, exercitando promoção, pré-condições, reprovação por saúde, restauração de rota, rollback, versão/digest imutável e preservação de volume.
