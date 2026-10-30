# Modelo de ameaças

## Ativos

- Disponibilidade das aplicações e do edge (Traefik).
- Integridade das imagens e do que é implantado.
- Segredos de aplicação, Docker Secrets e tokens do GitHub.
- Ledger de releases e backups de configuração.
- Logs e métricas de disponibilidade.
- Acesso ao host e ao Docker daemon.

## Atores

- Atacante externo sem credenciais.
- Usuário autenticado com acesso a Grafana/Uptime Kuma.
- Insider com acesso ao GitHub, ao runner ou ao servidor.
- Dependência ou imagem comprometida.
- Erro humano do operador.

## Fronteiras e premissas

- O host é o perímetro principal; root no host ou no grupo `docker` é game over.
- O runner é tratado como ambiente de risco: executa código de PR? Não. O
  workflow de deploy usa environment protegido e só roda em `main`/tag aprovada.
- O proxy do socket reduz, mas não elimina, o risco do acesso ao Docker.
- TLS termina no Traefik; serviços internos falam HTTP na rede overlay.

## STRIDE

| Categoria | Cenário | Controle | Residual |
|---|---|---|---|
| Spoofing | acesso ao dashboard com credencial fraca | basic auth com hash, TLS, rate limit | força bruta/distribuída; usar SSO no futuro |
| Tampering | imagem/tag trocada sem revisão | SemVer, digest, SHA de actions, SBOM/proveniência, Cosign | comprometimento da conta GitHub/registry |
| Repudiation | não saber quem implantou | ledger com autor, commit, checksum; logs do runner | logs podem ser apagados por root |
| Information disclosure | segredo em Git/log/histórico | Gitleaks, Docker Secrets, `__FILE`, `.env` ignorado, logs sem valores | vazamento por aplicação mal escrita |
| Denial of service | flood no edge ou disco cheio | rate limit, limites de recursos, retenção Loki, alerta de disco | DDoS volumétrico; sem scrubber/WAF dedicado |
| Elevation of privilege | container escapa ou usa socket | rootfs read-only, cap-drop, socket proxy, usuário não-root na app | kernel/Docker 0-day; runner root-equivalent |
| Supply chain | dependência/ação maliciosa | versões/digests fixos, Dependabot, CodeQL, Trivy, revisão humana | ataque ao upstream antes do pin |
| Insider | operador altera produção sem revisão | environment, branch protection, ledger, runbooks | root sempre pode contornar |

## Riscos aceitos

1. **Runner com grupo docker**: um workflow comprometido pode virar root. A
   mitigação é revisão de PR, environment protegido, token efêmero e runner
   dedicado; não há sandbox forte no host.
2. **Host único**: indisponibilidade de hardware/rede não é coberta por HA.
3. **Socket proxy**: reduz a API exposta, mas ainda é um caminho privilegiado.
4. **Dados de aplicação**: backup/restore de volumes é responsabilidade da
   aplicação; o projeto só fornece o exemplo.
5. **Migração de schema**: rollback de aplicação não reverte banco.

## O que não protegemos

- Ataque físico, hypervisor ou provedor de nuvem.
- Phishing de operadores.
- DDoS volumétrico sem mitigação upstream.
- Vulnerabilidades em serviços de terceiros fora do nosso controle.
- Configurações de demo local (TLS self-signed, registry local, portas locais).

## Revisão

Revisar este documento a cada mudança de arquitetura, novo serviço exposto,
mudança no runner ou incidente de segurança. Registrar a decisão em um ADR
quando a mitigação alterar o desenho.
