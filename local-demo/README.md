# Demo local

Demonstração do fluxo real da plataforma em um Docker Desktop com Swarm de nó único. Não é ambiente de produção.

## O que é real aqui

- Docker Swarm, serviços, overlay `public`, health check profundo e volume persistente.
- Traefik v3 com provider de arquivo, troca de rota a quente e TLS.
- O mesmo CLI `ops-deploy` do entregável, com ledger e rollback.
- Imagens construídas e publicadas em registry local.
- Grafana + Loki + Alloy para logs e Uptime Kuma para disponibilidade.

## O que é adaptado

- TLS autoassinado (sem Let's Encrypt/DNS público).
- Registry local em `127.0.0.1:5000` no lugar do GHCR.
- Domínios `*.127.0.0.1.nip.io` (precisam de DNS público para resolver).
- Runner do GitHub e pipeline não são executados.
- Uptime Kuma e Grafana começam sem monitores/dashboards prontos.

## Pré-requisitos

- Docker Desktop com Linux containers e Swarm habilitável.
- Git Bash (usa `bash`, `openssl` e `cygpath`).
- Portas 80, 443 e 5000 livres.
- Acesso à internet para baixar imagens e resolver `nip.io`.

## Subir

No Git Bash ou WSL:

```bash
cd local-demo
./scripts/up.sh
```

O script:

1. Inicializa o Swarm (se necessário) e cria as redes `public`/`internal`.
2. Gera credenciais aleatórias e cria os segredos locais `traefik_dashboard_users` e `grafana_admin_password`; grava tudo em `local-demo/state/credentials.env` (ignorado pelo Git).
3. Implanta a stack `demo-platform` (Traefik, registry, Uptime Kuma, Loki, Alloy, Grafana).
4. Constrói e publica as imagens `1.0.0`, `1.0.1` e `2.0.0`.
5. Executa `ops-deploy bootstrap demo-app 1.0.0`.

## Executar o roteiro

```bash
./scripts/demo.sh
```

O roteiro mostra:

1. `status` e `verify` da versão 1.0.0.
2. Deploy saudável de 1.0.1 (troca de slot).
3. Deploy de 2.0.0 com dependência quebrada: recusado, tráfego permanece em 1.0.1.
4. Rollback para 1.0.0 e auditoria do ledger.

## URLs

| Serviço | URL | Acesso |
|---|---|---|
| Aplicação | `https://demo.127.0.0.1.nip.io/` | público |
| Saúde | `bash local-demo/scripts/ops verify demo-app` | interno (sem exposição pública) |
| Traefik | `https://traefik.127.0.0.1.nip.io/` | credenciais em `local-demo/state/credentials.env` |
| Grafana | `https://grafana.127.0.0.1.nip.io/` | credenciais em `local-demo/state/credentials.env` |
| Uptime Kuma | `https://monitor.127.0.0.1.nip.io/` | criar conta local |

As credenciais são geradas no primeiro `up.sh` e ficam em `local-demo/state/credentials.env`. Para lê-las:

```bash
cat local-demo/state/credentials.env
```

Se você já tinha segredos de uma versão anterior, remova-os e apague o arquivo de credenciais antes de rodar o `up.sh` para gerar credenciais novas:

```bash
docker secret rm traefik_dashboard_users grafana_admin_password
rm -f local-demo/state/credentials.env
```

Em um volume Grafana já inicializado, o usuário e a senha do administrador ficam gravados no banco. Para usar as credenciais novas, remova o volume `demo-platform_grafana_data` ou altere a senha pela interface.

Aceite o aviso de certificado autoassinado no navegador.

## Comandos úteis

```bash
# status e saúde
bash local-demo/scripts/ops status demo-app
bash local-demo/scripts/ops verify demo-app

# novo deploy depois de publicar a imagem
bash local-demo/scripts/ops deploy demo-app 1.0.2

# rollback
bash local-demo/scripts/ops rollback demo-app

# logs de um slot
docker service logs --since 10m app-demo-app-blue
docker service logs --since 10m app-demo-app-green

# estado do Swarm
docker service ls
docker stack services demo-platform
```

## Monitoramento

No Uptime Kuma, crie dois monitores para `demo-app`:

- `https://demo.127.0.0.1.nip.io/` (disponibilidade pública, aceitar certificado inválido).
- `http://traefik:8081/ping` (saúde interna do Traefik; retorna `OK`).

No Grafana, a datasource Loki já está provisionada. Consultas:

```logql
{app="demo-app"} | json
{app="demo-app"} | json | level="error"
```

## Limpar

```bash
./scripts/down.sh
```

A stack é removida; volumes, segredos e o ledger em `local-demo/state/` são preservados. Para remover tudo:

```bash
docker stack rm demo-platform
docker secret rm traefik_dashboard_users grafana_admin_password
docker volume rm demo-platform_registry_data demo-platform_uptime_data \
  demo-platform_loki_data demo-platform_alloy_data demo-platform_grafana_data
docker network rm public internal
docker swarm leave --force
rm -rf local-demo/dynamic/*.yml local-demo/state
```
