# Runbook: homologação em Ubuntu Server 24.04

Este runbook leva um host limpo ao ponto de executar os seis critérios de
[`docs/aceite.md`](../docs/aceite.md) sem adicionar funcionalidades. Ele usa os
scripts, a CLI e os runbooks que já existem no repositório.

## 0. Resultado esperado

- Ubuntu Server 24.04 LTS com SSH por chave, UFW, fail2ban, auditd, Docker e
  Swarm de um nó.
- Plataforma no ar: Traefik, Uptime Kuma, Grafana, Loki, Alloy e socket proxy.
- `demo-app` publicado no GHCR e operado por `ops-deploy`.
- Evidências dos seis critérios preenchidas em `docs/aceite.md`.

## 1. Pré-requisitos

### 1.1 Host

- Ubuntu Server 24.04 LTS, 4 vCPU, 8 GB de RAM e 80 GB de disco.
  Para um smoke test, 2 vCPU, 4 GB e 40 GB são suficientes.
- IPv4 público e portas 22, 80 e 443 liberadas no firewall do provedor.
- Acesso inicial por chave SSH (ou console do provedor).

### 1.2 DNS

Crie os registros antes de subir a plataforma. O ACME usa HTTP-01 na porta 80.

| Nome | Tipo | Valor |
|---|---|---|
| `traefik.<DOMAIN>` | A | `<IP_PUBLICO>` |
| `monitor.<DOMAIN>` | A | `<IP_PUBLICO>` |
| `grafana.<DOMAIN>` | A | `<IP_PUBLICO>` |
| `<APP_DOMAIN>` | A | `<IP_PUBLICO>` |

Se o provedor permitir, um wildcard `*.<DOMAIN>` cobre os quatro nomes.

### 1.3 GitHub e GHCR

- Acesso de administrador ao repositório de infraestrutura.
- Environment `production` com revisor obrigatório.
- Runner self-hosted com os labels `self-hosted,linux,deploy`.
- Para o pipeline completo, o `demo-app` precisa estar em repositório próprio:
  o workflow está em `apps/demo-app/.github/workflows/deploy.yml` e passa a
  valer quando esse diretório vira a raiz do repositório.
- Tokens do GHCR: leitura (`read:packages`) para o servidor e escrita
  (`write:packages`) para a publicação manual.

### 1.4 Segredos e acessos

- Chave SSH do operador.
- Senha do dashboard do Traefik.
- Senha do Grafana (gerada no host).
- Token GHCR de leitura e token de escrita para publicação manual.
- Webhook de alerta (opcional).

Nunca grave segredos no Git. Mantenha-os no cofre da equipe.

## 2. Provisionar o host

### 2.1 Opção A: VPS com cloud-init

Copie o template e substitua a chave pública:

```bash
cp scripts/homologacao/cloud-init.yaml /tmp/homologacao.yaml
sed -i "s|REPLACE_WITH_SSH_PUBLIC_KEY|$(cat ~/.ssh/id_ed25519.pub)|" /tmp/homologacao.yaml
```

Use `/tmp/homologacao.yaml` como user-data na criação da VPS. O cloud-init
cria o usuário `ops`, instala os pacotes básicos e clona o repositório em
`/opt/deploy-platform-src`. Ele não mexe no SSH nem no firewall para evitar
lockout.

Com Multipass local (sem IP público, útil apenas para smoke test):

```bash
multipass launch 24.04 --name homologacao --cpus 4 --memory 8G --disk 80G \
  --cloud-init /tmp/homologacao.yaml
multipass shell homologacao
```

### 2.2 Opção B: host já instalado

```bash
sudo adduser ops
sudo usermod -aG sudo ops
sudo install -d -m 0700 -o ops -g ops /home/ops/.ssh
sudo tee /home/ops/.ssh/authorized_keys >/dev/null <<'EOF'
<SUA_CHAVE_PUBLICA>
EOF
sudo chown ops:ops /home/ops/.ssh/authorized_keys
sudo chmod 600 /home/ops/.ssh/authorized_keys
```

Teste o login por chave em outra sessão antes de continuar.

### 2.3 Clonar o repositório

Se usou o cloud-init da seção 2.1, o clone já existe; pule para o checkout.

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/iVawly/deploy-automatico.git /opt/deploy-platform-src
sudo chown -R ops:ops /opt/deploy-platform-src
cd /opt/deploy-platform-src
```

Para uma execução reprodutível, faça checkout da tag ou commit que será
homologado:

```bash
git checkout <TAG_OU_COMMIT>
```

## 3. Base do host

```bash
cd /opt/deploy-platform-src
sudo apt-get install -y apache2-utils jq openssl
sudo ./scripts/server/harden-system.sh
sudo ./scripts/server/harden-ssh.sh
sudo usermod -aG ops ops
sudo ./scripts/server/firewall.sh
```

Se o SSH usar outra porta:

```bash
SSH_PORT=<PORTA> sudo -E ./scripts/server/firewall.sh
```

Reinicie para validar sysctls e auditd:

```bash
sudo reboot
```

Depois do reboot, confirme:

```bash
sudo systemctl is-active fail2ban auditd
sudo ufw status verbose
sudo sysctl kernel.dmesg_restrict
```

## 4. Docker e Swarm

```bash
cd /opt/deploy-platform-src
sudo ./scripts/server/install-docker.sh
sudo ./scripts/server/init-swarm.sh <IP_DO_HOST>
```

Use o IP privado do host quando ele estiver atrás de NAT; use o IP público
quando o host tiver o endereço diretamente. Guarde a chave de autolock no
cofre. Confira:

```bash
sudo docker info --format '{{.Swarm.LocalNodeState}}'
sudo docker node ls
```

Depois de qualquer reboot, desbloqueie o Swarm antes de esperar serviços:

```bash
sudo docker swarm unlock
```

## 5. Segredos da plataforma

```bash
export TRAEFIK_ADMIN_USER="admin"
read -rsp "Senha do dashboard Traefik: " TRAEFIK_ADMIN_PASSWORD; echo
printf '%s\n' "$(htpasswd -nbB "$TRAEFIK_ADMIN_USER" "$TRAEFIK_ADMIN_PASSWORD")" \
  | sudo docker secret create traefik_dashboard_users -

GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24)"
printf '%s' "$GRAFANA_ADMIN_PASSWORD" | sudo docker secret create grafana_admin_password -
printf 'Guarde a senha do Grafana: %s\n' "$GRAFANA_ADMIN_PASSWORD"
unset TRAEFIK_ADMIN_PASSWORD GRAFANA_ADMIN_PASSWORD

sudo docker secret ls
```

Se um segredo já existir, não recrie: apenas confirme com `docker secret ls`.

## 6. Instalar a plataforma

```bash
cd /opt/deploy-platform-src
sudo ./scripts/install.sh
sudo chmod 600 /opt/deploy-platform/.env
sudoedit /opt/deploy-platform/.env
```

Valores mínimos do `.env`:

```dotenv
DOMAIN=<DOMAIN>
ACME_EMAIL=<EMAIL>
DEPLOY_ROOT=/opt/deploy-platform
GRAFANA_ADMIN_USER=admin
```

Ajuste a aplicação piloto:

```bash
sudoedit /opt/deploy-platform/deploy/apps/demo-app/app.conf
```

```dotenv
APP_DOMAIN=<APP_DOMAIN>
APP_IMAGE_REPO=ghcr.io/<OWNER>/demo-app
```

Mantenha `APP_VERIFY_PUBLIC=1` para validar a rota pública após a troca.

## 7. Subir a plataforma

```bash
sudo /opt/deploy-platform/scripts/bootstrap-platform.sh
sudo docker stack services platform
```

Espere todos os serviços ficarem em `1/1`. Valide o TLS:

```bash
curl -sS -o /dev/null -w 'monitor %{http_code}\n' https://monitor.<DOMAIN>
curl -sS -o /dev/null -w 'grafana %{http_code}\n' https://grafana.<DOMAIN>
curl -sS -o /dev/null -w 'traefik %{http_code}\n' https://traefik.<DOMAIN>
```

`monitor` e `grafana` devem responder `200` ou `302`. `traefik` deve responder
`401` sem credenciais; com o usuário e a senha do dashboard, deve responder
`200`. Se o ACME falhar, confira DNS, porta 80 e os logs:

```bash
sudo docker service logs platform_traefik --tail 100
```

## 8. Runner e acesso ao GHCR

Registre o runner no repositório onde o workflow de deploy vai rodar (o repo
do `demo-app`, quando separado). Em GitHub → Settings → Actions → Runners →
New self-hosted runner, copie o token e execute:

```bash
export RUNNER_URL="https://github.com/<OWNER>/<APP_REPO>"
export RUNNER_TOKEN="<TOKEN>"
export RUNNER_LABELS="self-hosted,linux,deploy"
cd /opt/deploy-platform-src
sudo -E ./scripts/server/install-runner.sh
sudo systemctl status actions.runner.* --no-pager
```

O runner roda como `deployer` e usa o Docker do host. Faça o login manual no
GHCR para o primeiro bootstrap:

```bash
export GHCR_READ_TOKEN="<TOKEN_READ_PACKAGES>"
printf '%s' "$GHCR_READ_TOKEN" \
  | sudo -u deployer docker login ghcr.io -u "<GITHUB_USER>" --password-stdin
sudo -u deployer docker pull ghcr.io/<OWNER>/demo-app:1.0.0
```

## 9. Publicar a imagem do demo-app

### 9.1 Caminho rápido: publicação manual

Em uma máquina com Docker e acesso ao GHCR:

```bash
cd apps/demo-app
export OWNER="<OWNER>"
export VERSION="1.0.0"
export GHCR_TOKEN="<TOKEN_WRITE_PACKAGES>"
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$OWNER" --password-stdin
docker buildx build --push --platform linux/amd64 \
  --build-arg VERSION="$VERSION" \
  --build-arg REVISION="$(git rev-parse HEAD)" \
  --build-arg CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t "ghcr.io/$OWNER/demo-app:$VERSION" .
```

Use o mesmo valor de `APP_IMAGE_REPO` no `app.conf`. O owner precisa estar em
minúsculas, como exige o Docker.

Para o cenário de versão defeituosa, publique uma imagem com a dependência
quebrada:

```bash
export BAD_VERSION="1.1.0-bad"
docker buildx build --push --platform linux/amd64 \
  --build-arg VERSION="$BAD_VERSION" \
  --build-arg REVISION="$(git rev-parse HEAD)" \
  --build-arg CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg DEPENDENCY_URL="http://127.0.0.1:1" \
  -t "ghcr.io/$OWNER/demo-app:$BAD_VERSION" .
```

### 9.2 Caminho completo: pipeline no repo do demo-app

Crie um repositório vazio `<OWNER>/demo-app` no GitHub e, a partir do repo de
infraestrutura:

```bash
rm -rf /tmp/demo-app-repo && mkdir -p /tmp/demo-app-repo
git archive HEAD apps/demo-app | tar -x -C /tmp/demo-app-repo --strip-components=2
cd /tmp/demo-app-repo
git init -b main
git add .
git commit -m "Piloto demo-app"
git remote add origin git@github.com:<OWNER>/demo-app.git
git push -u origin main
```

O workflow `deploy.yml` agora roda testes em pull requests e só faz
build/deploy em tags `v*` ou `workflow_dispatch`. Configure o environment
`production` com revisor e registre o runner nesse repositório.

Primeira versão: publique `1.0.0` pelo caminho manual ou deixe a tag `v1.0.0`
construir a imagem e falhar no deploy por falta de bootstrap. Depois:

```bash
sudo -u deployer ops-deploy bootstrap demo-app 1.0.0
```

Para exercitar o pipeline de ponta a ponta, publique uma versão saudável
`1.1.0`:

```bash
git tag -a v1.1.0 -m "release 1.1.0"
git push origin v1.1.0
```

Acompanhe o workflow `deploy` no GitHub. O job `build-and-deploy` roda no
runner self-hosted e chama `ops-deploy deploy demo-app 1.1.0`.

## 10. Bootstrap da aplicação

```bash
sudo -u deployer ops-deploy bootstrap demo-app 1.0.0
sudo -u deployer ops-deploy status demo-app
sudo -u deployer ops-deploy verify demo-app
curl -fsS https://<APP_DOMAIN>/
```

Esperado: `"healthy":true`, versão `1.0.0` no slot `blue` e HTTP `200` na URL
pública. Se o pull falhar com `401`/`403`, confira o login do `deployer` no
GHCR e a visibilidade do pacote.

## 11. Executar os critérios de aceite

### Critério 1 — testes antes da implantação

No repo do `demo-app`, abra um PR que quebra um teste (por exemplo, altere uma
asserção em `tests/test_app.py`). O job `test` falha e `build-and-deploy` é
ignorado. Guarde o link do run.

Alternativa sem repo separado: crie uma tag de teste com o teste quebrado. O
job `test` falha antes do build.

### Critério 2 — versão defeituosa não substitui a saudável

Em um terminal, acompanhe os logs dos dois slots:

```bash
sudo docker service logs -f app-demo-app-blue app-demo-app-green
```

Em outro terminal, registre o estado e tente o deploy ruim:

```bash
sudo -u deployer ops-deploy status demo-app --json | tee /tmp/status-antes.json
sudo -u deployer ops-deploy deploy demo-app 1.1.0-bad; echo "exit=$?"
sudo -u deployer ops-deploy status demo-app --json | tee /tmp/status-depois.json
curl -fsS -o /dev/null -w '%{http_code}\n' https://<APP_DOMAIN>/
```

Esperado: o deploy retorna erro, o status continua em `1.0.0`, a URL pública
continua `200` e o candidato é reduzido a zero.

### Critério 3 — indisponibilidade gera alerta

Configure os monitores do Uptime Kuma conforme
[`docs/observabilidade.md`](../docs/observabilidade.md): intervalo `30s`,
retries `3`, notificação de recuperação habilitada. Use **Test Notification**
antes do teste real.

```bash
ACTIVE_SLOT="$(sudo -u deployer ops-deploy status demo-app --json | jq -r .active_slot)"
sudo docker service scale "app-demo-app-${ACTIVE_SLOT}=0"
```

Aguarde o alerta (até 2 minutos) e capture a notificação. Restaure:

```bash
sudo docker service scale "app-demo-app-${ACTIVE_SLOT}=1"
```

Confirme a notificação de recuperação no mesmo canal.

### Critério 4 — causa identificável pelos logs

Após o deploy defeituoso do critério 2, consulte o Grafana:

```logql
{app="demo-app"} | json | level="error"
{app="demo-app", version="1.1.0-bad"} | json
```

Localize o `health check failed` e o erro da dependência. Se os logs do
candidato já tiverem sido removidos, use a captura feita com
`docker service logs` no critério 2. Guarde a consulta e o horário.

### Critério 5 — rollback documentado

Publique e implante uma versão saudável `1.1.0` (pipeline ou manual), grave um
marcador no volume e faça o rollback:

```bash
sudo docker run --rm -v demo-app-data:/data busybox sh -c 'echo aceite > /data/aceite'
time sudo -u deployer ops-deploy rollback demo-app
sudo -u deployer ops-deploy status demo-app
sudo -u deployer ops-deploy verify demo-app
sudo docker run --rm -v demo-app-data:/data busybox cat /data/aceite
sudo tail -n 5 /var/lib/ops-deploy/releases.jsonl
```

Esperado: `1.0.0` ativo, `"healthy":true`, marcador preservado, registro
`"action":"rollback"` e tempo total abaixo de 5 minutos.

### Critério 6 — outra pessoa executa pela documentação

Entregue este runbook a um segundo integrante. Ele deve executar um deploy e
um rollback sem ajuda, usando apenas a documentação. Registre nome, data e
tempo em [`docs/aceite.md`](../docs/aceite.md).

## 12. Evidências e encerramento

- Preencha a tabela de `docs/aceite.md` com data, responsável e link/print.
- Rode `sudo /opt/deploy-platform/scripts/server/backup-config.sh` e copie o
  arquivo e o checksum para fora do host.
- Revise o gate de go-live em [`docs/producao.md`](../docs/producao.md).
- Guarde os logs dos workflows, saídas de `status`/`verify`, consultas do
  Grafana e notificações do Uptime Kuma na pasta de evidências da equipe.

## 13. Limpeza e reconstrução

Este host é descartável. Para recomeçar do zero, remova a stack, os serviços
da aplicação e os volumes **somente após copiar as evidências**:

```bash
sudo docker stack rm platform
sudo docker service rm app-demo-app-blue app-demo-app-green
sudo docker volume rm demo-app-data traefik_letsencrypt uptime_data loki_data alloy_data grafana_data
sudo docker swarm leave --force
```

Para reconstruir a plataforma sem apagar dados, siga
[`runbooks/reconstrucao-servidor.md`](reconstrucao-servidor.md).

## 14. Diagnóstico rápido

| Sintoma | Verificação |
|---|---|
| ACME não emite certificado | DNS, porta 80, `docker service logs platform_traefik` |
| `docker pull` do GHCR falha | login do `deployer`, visibilidade do pacote, escopo do token |
| Runner offline | `systemctl status actions.runner.*`, labels, grupo `docker` |
| Swarm bloqueado após reboot | `sudo docker swarm unlock` |
| `bootstrap` recusado | já existe release estável; use `deploy` |
| Porta 80/443 ocupada | `ss -lntp` e `docker service ls` |
| Alerta demora mais de 2 min | intervalo/retries do monitor e canal de notificação |
