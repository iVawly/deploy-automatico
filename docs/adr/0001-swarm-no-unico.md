# ADR 0001 — Swarm de nó único

## Contexto

A operação tem um servidor Ubuntu e uma equipe pequena. Kubernetes exigiria mais
componentes, custo cognitivo e recursos sem benefício proporcional. O requisito é
deploy repetível, healthcheck, rollback e segredos com baixo custo operacional.

## Decisão

Usar Docker Swarm com um nó manager. Serviços usam redes overlay `public` e
`internal`, Docker Secrets, placements no manager e volumes locais.

## Consequências

- Positivas: instalação simples, API estável, secrets nativos, roteamento por
  serviço e recuperação documentada.
- Negativas: sem HA real de host/rede; upgrade do Docker é janela de manutenção;
  volumes locais exigem backup próprio.
- Segurança: o manager acumula controle do cluster; acesso ao Docker é
  equivalente a root. O host e o runner são tratados como perímetro crítico.

## Alternativas

- Kubernetes/k3s: mais poderoso, mas desproporcional para um host e uma equipe
  pequena.
- systemd + containers: menos abstração, mas exigiria reimplementar roteamento,
  secrets e healthcheck.
- Serviço gerenciado: reduz operação, mas adiciona custo e dependência externa.
