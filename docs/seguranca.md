# Segurança

## Regras gerais

- Nenhuma senha, token, chave privada ou certificado com chave privada vai para o Git. A varredura `gitleaks` roda no pipeline e bloqueia a promoção.
- O repositório contém apenas `.env.example` e modelos sem valores reais.
- Segredos de aplicação ficam em Docker Secrets; segredos de pipeline ficam nos segredos do GitHub.
- Logs não recebem valores de segredos; a aplicação registra apenas que o valor foi omitido.
- Vulnerabilidades devem ser reportadas em privado conforme `SECURITY.md`; não abra issue pública com detalhes exploráveis.

## Supply chain

- Imagens de plataforma são fixadas por digest (`imagem:tag@sha256:...`); atualizações chegam por PR do Dependabot.
- Imagens de aplicação usam SemVer imutável e são construídas no CI a partir do commit revisado.
- O CI executa gitleaks, Trivy (filesystem e imagem), Hadolint, ShellCheck, actionlint e testes.
- O workflow de publicação gera SBOM e atestação de proveniência; quando habilitado, assina a imagem com Cosign keyless.
- GitHub Actions são referenciadas por SHA completo; tags móveis não são aceitas em `main`.
- O runner baixa a versão fixada e valida o SHA-256 do pacote antes de extrair.

## Containers

- Slots de aplicação: rootfs read-only, `cap-drop ALL`, `/tmp` em tmpfs, limites de CPU/memória/PIDs e rotação de logs.
- Plataforma: rootfs read-only onde suportado, capabilities mínimas e limites de recursos.
- O Docker Swarm 29.8 não expõe `no-new-privileges` no CLI de serviço; a defesa efetiva vem de usuário não-root, rootfs read-only, `cap-drop ALL` e socket proxy.
- Alloy não monta `/var/run/docker.sock`; fala com `docker-socket-proxy` em rede interna, com API somente leitura.
- O dashboard do Traefik exige basic auth; Grafana e Uptime Kuma nunca são expostos sem TLS.
- TLS mínimo 1.2, HSTS, `nosniff`, `frameDeny` e rate limit por IP no edge.

## Docker Secrets

```bash
# criar (o valor nunca é passado por argumento de linha de comando)
openssl rand -base64 32 | docker secret create demo_app_database_url -
printf '%s' '<valor>' | docker secret create demo_app_database_url_v2 -

# usar em app.conf
APP_SECRETS="demo_app_database_url"
```

Montagem padrão em `/run/secrets/<nome>`, em tmpfs. Para o serviço receber segredo por variável de ambiente, a aplicação deve lê-lo do arquivo, não o contrário.

### Rotação sem alterar código

1. Crie o segredo com sufixo de versão (`_v2`).
2. Atualize `deploy/apps/<app>/app.conf` para o novo nome.
3. `sudo -u deployer ops-deploy deploy <app> <mesma-versao>` (a imagem é reutilizada).
4. Valide `ops-deploy verify <app>`.
5. Remova o segredo antigo após a janela de segurança.

## Acesso ao servidor

- SSH apenas por chave; senha e autenticação interativa desabilitadas (`scripts/server/harden-ssh.sh`).
- Root não faz login por senha (`prohibit-password`).
- Grupo `ops` para sudo; revise trimestralmente.
- Firewall padrão nega entrada e tráfego roteado, libera somente 22/80/443; SSH tem rate limit.
- `harden-system.sh` aplica sysctl, journald persistente, auditd, fail2ban e atualizações de segurança automáticas.
- Remova a chave do usuário em `~/.ssh/authorized_keys` ao desligar um integrante e teste a recusa.

## Runner

O usuário `deployer` pertence ao grupo `docker`, o que equivale a root no host. Controles compensatórios:

- conta sem shell de login e sem sudo;
- runner auto-hospedado escuta apenas conexões de saída;
- token de registro efêmero, usado uma única vez;
- permissões do workflow limitadas a `contents: read` e `packages: write`;
- segredos do repositório com escopo mínimo;
- revogação: remover o runner em GitHub → Settings → Actions → Runners e apagar `/opt/actions-runner/.credentials`.

## Chaves e recuperação

- Chave de autolock do Swarm e senhas de inicialização ficam em cofre fora do servidor.
- Backup de configuração com `scripts/server/backup-config.sh`, checksum SHA-256 e retenção de 30 dias, copiado para fora do host.
- Restauração com `scripts/server/restore-config.sh`, que valida o checksum e recusa caminhos perigosos.
- Teste de restauração registrado em `docs/aceite.md`.

## Resposta a vazamento

1. Revogue a credencial no provedor de origem.
2. Gire o segredo e reimplante o serviço afetado.
3. Remova a credencial do histórico com `git filter-repo` e force a rotação de todos os clones.
4. Registre o incidente em `runbooks/incidentes.md`.
