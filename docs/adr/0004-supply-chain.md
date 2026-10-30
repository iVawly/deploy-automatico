# ADR 0004 — Imagens imutáveis e supply chain

## Contexto

Tags como `latest` e actions por tag móvel permitem que o artefato implantado
mude sem revisão. O objetivo é que o que foi testado seja o que roda, e que a
origem seja verificável.

## Decisão

- Aplicações usam SemVer imutável (`1.4.0`), nunca `latest`.
- Imagens de plataforma são referenciadas com digest (`imagem:tag@sha256:...`).
- GitHub Actions são referenciadas por SHA completo.
- O CI executa Gitleaks, Trivy, Hadolint, actionlint e testes.
- A publicação gera SBOM e proveniência; Cosign keyless assina a imagem.
- O runner é instalado em versão fixa com checksum e auto-update desabilitado.

## Consequências

- Positivas: reprodutibilidade, detecção de regressão de segurança, auditoria de
  origem, atualização intencional.
- Negativas: PRs de atualização exigem revisão e smoke test; imagens antigas
  precisam de processo de upgrade; a assinatura depende do OIDC do GitHub.
- Operação: atualizar digest/versão é uma mudança revisável, não um efeito
  colateral de `latest`.

## Alternativas

- Tags móveis: simples, mas não reprodutível.
- Apenas Dependabot sem digest: reduz trabalho, mas não fixa o artefato.
- Registry privado com política de retenção: complementar, não substitui o
  pinning.
