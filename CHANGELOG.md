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
- Backup com checksum/retenção e restore com validação de caminho.
- CI com Gitleaks, Trivy, Hadolint, actionlint, testes e smoke test da imagem;
  CodeQL, Scorecard, Dependabot e ações fixadas por SHA.

### Added

- `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `LICENSE`,
  `CHANGELOG.md`, templates de issue/PR e configuração de pre-commit.
- `docs/arquitetura.md`, `docs/ameacas.md`, `docs/producao.md` e ADRs.
- `scripts/server/harden-system.sh` e `scripts/server/restore-config.sh`.
- `make lint-yaml`, `make lint-actions`, `make lint-docker`, `make build`,
  `make security` e `make check`.

### Changed

- `ops-deploy` 1.1.0 aplica hardening padrão aos serviços.
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
