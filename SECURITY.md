# Política de segurança

## Versões suportadas

A branch `main` e a última release recebem correções de segurança. Tags antigas
não recebem backport por padrão; quem opera uma release anterior deve planejar a
atualização ou manter um fork com o patch aplicado.

## Como reportar

Não abra issue pública com detalhes exploráveis, provas de conceito ou dados de
clientes. Use **GitHub Security Advisories** no repositório:

1. Abra a aba **Security**.
2. Clique em **Report a vulnerability**.
3. Descreva impacto, versão/commit afetado, reprodução mínima e mitigação sugerida.

Se o recurso de advisory privado não estiver disponível, contate um mantenedor
diretamente pelo GitHub e combine um canal privado antes de enviar detalhes.

## O que esperar

- Confirmação de recebimento em até 3 dias úteis.
- Triagem inicial com classificação de severidade e próximo passo.
- Atualização durante a investigação; correção priorizada para achados críticos.
- Crédito na divulgação, se você quiser e se a política do projeto permitir.

Os prazos são objetivos de melhor esforço, não um SLA comercial.

## Escopo

Dentro do escopo:

- `scripts/ops-deploy`, scripts de instalação, hardening, backup e restore;
- workflows em `.github/workflows` e `apps/demo-app/.github/workflows`;
- `deploy/` (Traefik, platform stack, Loki, Alloy, Grafana);
- `apps/demo-app` (imagem e endpoint de saúde);
- documentação que descreva um procedimento inseguro.

Fora do escopo:

- falhas em Docker, Traefik, Grafana, Loki, Alloy, Uptime Kuma ou GitHub;
- provedor de nuvem, DNS, rede ou hardware;
- engenharia social, phishing e acesso físico;
- configurações deliberadamente inseguras documentadas como demo local
  (`local-demo/`, TLS self-signed, registry local).

## Modelo de segurança

O projeto assume um único host Linux, operado por uma equipe pequena. O objetivo
é reduzir o impacto de erro humano, credencial vazada e imagem comprometida, não
garantir resistência a um adversário com root no hypervisor.

Controles principais:

- **Segredos**: Docker Secrets em runtime; GitHub Secrets no pipeline; nada de
  valor real no Git. `local-demo/state/credentials.env` é gerado e ignorado.
- **Menor privilégio**: aplicações com rootfs read-only, `cap-drop ALL`,
  limites de recursos e `/tmp` em tmpfs. Alloy não monta o
  socket bruto do Docker; usa um proxy somente leitura em rede interna.
- **Supply chain**: imagens de plataforma por digest, ações do GitHub por SHA,
  runner com versão e checksum fixados, SBOM/proveniência e assinatura Cosign no
  fluxo de publicação.
- **Borda**: TLS 1.2+, HSTS, `nosniff`, `frameDeny`, rate limit, dashboard do
  Traefik com basic auth e portas internas não publicadas.
- **Host**: SSH somente por chave, firewall default-deny, fail2ban, auditd,
  atualizações automáticas, journald persistente e backup com checksum.
- **Observabilidade**: logs estruturados com `app`, `slot`, `version` e
  `X-Request-ID`; alertas independentes do ciclo de deploy.

## Responsabilidades do operador

- Revisar e aprovar PRs de dependências e digests de imagem.
- Rotacionar segredos após desligamento de pessoa, suspeita de vazamento ou
  mudança de provedor.
- Validar restore de backup e rollback em ambiente descartável.
- Monitorar alertas, disco e falhas de runner.
- Manter o host e o Docker atualizados; o script não substitui gestão de patches.
- Não executar código não revisado no runner. O usuário `deployer` pertence ao
  grupo `docker`, o que equivale a root no host.

## Divulgação

A divulgação coordenada é preferida. Não publique detalhes antes de uma correção
ou mitigação estar disponível. O projeto pode publicar um advisory assim que a
correção for liberada.
