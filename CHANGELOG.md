# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento SemVer para o CLI e para a plataforma.

## [Unreleased]

### Security

- Credenciais fixas removidas do demo local e dos exemplos; o demo gera
  usuário/senha aleatórios em `local-demo/state/credentials.env` (ignorado).
- Imagens da plataforma atualizadas e fixadas por digest.
- Alloy passou a acessar o Docker via `docker-socket-proxy` somente leitura em
  rede interna; o socket bruto não é mais montado no coletor.
- Slots de aplicação com rootfs read-only, `cap-drop ALL`,
  limites de CPU/memória/PIDs, `/tmp` em tmpfs e rotação de
  logs.
- Traefik com TLS mínimo 1.2, HSTS, headers de segurança, rate limit e ping.
- Runner com versão/checksum fixados e auto-update desabilitado.
- Host com sysctl, auditd, fail2ban, journald persistente e atualizações
  automáticas.
- Backup com checksum/retenção e restore com validação de caminho; symlinks,
  hardlinks e tipos especiais no tar são recusados antes da extração.
- `ops-deploy deploy`/`bootstrap` exigem digest (`sha256:...`); o ledger registra
  o digest e o pipeline passa o digest do build.
- CI com Gitleaks, Trivy, Hadolint, actionlint, testes e smoke test da imagem;
  CodeQL, Scorecard, Dependabot e ações fixadas por SHA.
- SSH endurecido com drop-in `00-ops-deploy.conf` (vence o `50-cloud-init.conf`),
  `AllowGroups ops`, remoção do `99-` legado e sudo do grupo `ops` em
  `/etc/sudoers.d/10-ops-deploy` validado por `visudo`; o prefixo `10-` preserva
  regra NOPASSWD específica de operador sem senha (ex.: usuário do cloud-init).
- Dependabot passou a acompanhar as imagens das stacks `deploy` e `local-demo`.
- `X-Request-ID` do demo-app agora é validado (`[A-Za-z0-9._:-]`, até 128
  caracteres) antes de ser refletido, bloqueando injeção/obs-fold de cabeçalho.
- `install-docker.sh` mescla `daemon.json` preservando `data-root`,
  `registry-mirrors` e chaves locais, em vez de sobrescrever o arquivo.
- `app.conf` valida flags de hardening e limites numéricos, evitando desligar
  `read-only`/PIDs silenciosamente com valores inválidos.

### Fixed

- `ops-deploy` não falha mais quando `docker service create` não expõe
  `--security-opt`; o `no-new-privileges` é aplicado quando disponível e o CLI
  avisa quando não for.
- `ops-deploy status` volta a listar os serviços da aplicação usando
  `docker service ls` com filtro por label.
- CLI instalado por symlink resolve o repositório em `/opt/deploy-platform`.
- Bootstrap funciona a partir do diretório instalado, independente do `cwd`.
- Workflow de deploy do `demo-app` na raiz do monorepo (tag `demo-app-v*`).
- Runbook de recuperação restaura configuração/`.env` antes do bootstrap e usa
  `recover` após restaurar o volume.
- Checksum de backup usa nome relativo e o restore compara apenas o hash.
- Demo local usa `OPS_DEPLOY_PROXY_HOST` derivado de `DEMO_STACK`, alinhado ao
  DNS `demo-platform_traefik`.
- `OPS_DEPLOY_DRY_RUN` virou preview seguro: não sonda, não grava rota/ledger e
  não adquire lock.
- Retry de `docker service create` detecta criação parcial e não falha com
  "name already in use".
- `HEALTHCHECK` do Dockerfile respeita `APP_PORT`.
- `bootstrap-platform.sh` detecta `.env` legível por grupo/outros em qualquer
  modo (ex.: `604`).
- `APP_SECRETS` não sofre expansão de glob, é validado antes de qualquer
  remoção/criação de serviço e exige primeiro caractere alfanumérico.
- CI roda shellcheck também em `scripts/ci/*.sh`; retry inválido falha com
  mensagem explícita em vez de usar o default.
- Dry-run não executa mais o `sleep` de drenagem; `recover`/`rollback` rejeitam
  argumentos extras; `APP_KEEP_VERSIONS` usa base decimal e normaliza zeros à
  esquerda.
- `local-demo/docker-compose.yml` normalizado (sem espaços no EOF), restaurando
  `make lint-yaml`.

### Added

- `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `LICENSE`,
  `CHANGELOG.md`, templates de issue/PR e configuração de pre-commit.
- `ops-deploy status` lista as últimas `APP_KEEP_VERSIONS` versões estáveis
  (padrão 5) com data de implantação e saúde, e expõe `stable_versions` no JSON.
- `docs/arquitetura.md`, `docs/ameacas.md`, `docs/producao.md` e ADRs.
- `scripts/server/harden-system.sh` e `scripts/server/restore-config.sh`.
- `make lint-yaml`, `make lint-actions`, `make lint-docker`, `make build`,
  `make security` e `make check`.

### Changed

- Stacks renomeadas para `deploy/docker-compose.yml` e
  `local-demo/docker-compose.yml` para o Dependabot acompanhar as imagens.
- `ops-deploy` 1.2.0 aplica hardening padrão aos serviços, usa retry com
  backoff em operações Docker, exige digest e lista versões estáveis no
  `status`.
- README reescrito para quickstart, arquitetura, segurança e limites.
- `docs/seguranca.md`, `docs/observabilidade.md`, `docs/ops-deploy.md` e
  runbooks atualizados.

## [0.1.0] - 2026-10-28

### Added

- CLI `ops-deploy` com deploy blue-green, rollback, verify e status.
- Stack de plataforma com Traefik, Grafana, Loki, Alloy e Uptime Kuma.
- Aplicação piloto `demo-app` com healthcheck profundo e logs JSON.
- Runbooks de deploy, rollback, alertas, incidentes, runner, recuperação e
  reconstrução do servidor.
- Testes Bats com dublês de Docker/curl e testes Python do demo-app.
