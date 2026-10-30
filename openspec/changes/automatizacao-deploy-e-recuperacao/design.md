# Design

## Context

Ver `proposal.md` para a motivação. O ponto de partida é um único servidor Ubuntu Server 24.04 com aplicações atualizadas manualmente, sem testes obrigatórios, sem verificação de saúde e sem observabilidade. Não há código de infraestrutura no projeto: tudo será criado nesta entrega.

Restrições que moldam o desenho: orçamento zero para plataforma, um único servidor, equipe de TI pequena, aplicações containerizáveis e necessidade de manter os sistemas no ar durante a implantação.

## Goals / Non-Goals

**Goals:**

- Base de execução reproduzível no servidor: Docker, orquestração leve, proxy, TLS automático e rede interna.
- Pipeline que bloqueia a promoção em caso de teste, varredura de segredo ou saúde reprovada.
- Implantação blue-green com troca de tráfego somente após saúde comprovada e rollback de um comando.
- Observabilidade mínima porém completa: disponibilidade, alerta, painel e logs correlacionáveis.
- Operação documentada e ensaiada por um segundo integrante da equipe.

**Non-Goals:**

- Alta disponibilidade entre servidores, tolerância à perda do host ou autoscaling.
- Kubernetes ou malha de serviços.
- Observabilidade de métricas de negócio, tracing distribuído e APM completo.
- Automação de migração de banco de dados; migrações continuam procedimento controlado com compatibilidade retrospectiva.
- Reescrita das aplicações; apenas adaptações mínimas de containerização, health endpoint e log estruturado.

## Decisions

### 1. Orquestração: Docker Swarm em nó único

Usar Docker Engine com Swarm inicializado em nó único.

**Por quê:** já vem no Docker, oferece agendamento com reinício automático, healthcheck por serviço, secrets nativos, `docker service update --rollback` e `docker service rollback`, com custo de operação baixo.

**Alternativas consideradas:**

- **Docker Compose + scripts:** simples, porém reinício, saúde e secrets exigiriam lógica própria.
- **k3s/Kubernetes:** recursos e complexidade incompatíveis com o servidor único e a equipe.
- **Kamal:** bom fluxo de deploy, mas adiciona uma ferramenta e um modelo de proxy próprios para resolver o que o Swarm já resolve.

**Limite conhecido:** Swarm em nó único não protege contra falha do host. Isso é aceito e tratado em riscos.

### 2. Estratégia de release: blue-green por slots

Cada aplicação terá dois serviços Swarm, `app-<nome>-blue` e `app-<nome>-green`, compartilhando o mesmo volume persistente e a mesma rede interna. Apenas um slot recebe tráfego do proxy por vez.

Fluxo do deploy:

1. Identificar o slot inativo.
2. Atualizar o slot inativo com a nova imagem e aguardar saúde profunda.
3. Se saudável, apontar a rota do proxy para o novo slot e validar pela URL pública.
4. Manter o slot anterior em execução (sem tráfego) por uma janela de segurança e registrá-lo como versão anterior.
5. Se qualquer etapa falhar, descartar o slot candidato e manter o slot ativo intacto.

**Por quê:** garante de forma explícita que tráfego só chega após saúde comprovada, e que a versão saudável continua completa e pronta para retorno, o que o rolling update nativo não assegura sozinho (o roteamento pode alcançar tarefas em execução antes do healthcheck).

**Alternativas consideradas:**

- **`docker service update` com `--update-order start-first` e `--update-failure-action rollback`:** menos peças, mas não impede tráfego para tarefa ainda não saudável e o rollback nativo cobre apenas uma versão anterior.
- **Rolling update com Traefik healthcheck:** reduz a janela, mas a decisão de promoção fica implícita e difícil de auditar.

### 3. Proxy e roteamento: Traefik v3 com provider de arquivo

Traefik v3 como reverse proxy na borda, TLS via ACME (Let's Encrypt) e roteamento por hostname. As rotas ficam em arquivos dinâmicos versionados (`dynamic/<app>.yml`), gerados pelo CLI de deploy e recarregados a quente.

**Por quê:** o provider de arquivo permite trocar o upstream de forma atômica e auditável, sem recriar serviços, e mantém o roteamento legível para a equipe. O ACME elimina renovação manual de certificados.

**Alternativas consideradas:**

- **Traefik com provider Swarm e labels:** troca de rota exigiria recriar o serviço do slot, o que confunde a promoção.
- **Nginx/Caddy com reload:** viável, porém o Traefik já entrega ACME, middlewares e descoberta com menos configuração.

### 4. CI/CD: GitHub Actions com runner auto-hospedado no servidor

Cada repositório de aplicação tem um workflow com as etapas: verificação de segredos (gitleaks), lint e testes, build e push da imagem para o GitHub Container Registry privado, deploy no slot inativo, verificação de saúde pública e promoção.

O runner é instalado como serviço systemd sob o usuário `deployer`, no mesmo servidor.

**Por quê:** sem custo adicional, sem abrir SSH de entrada para a internet, sem armazenar chave de deploy em segredo de terceiros; o runner inicia a conexão de saída e executa localmente.

**Alternativas consideradas:**

- **Runner hospedado + deploy por SSH:** exigiria exposição de SSH e gestão de chave privada no CI.
- **GitLab CI/Gitea Actions:** a estrutura de etapas é equivalente; a troca fica restrita aos arquivos de pipeline, mantendo o restante do desenho.

**Premissa:** hospedagem Git compatível com GitHub Actions. Se o cliente usar GitLab ou Gitea, apenas o arquivo de pipeline e o registro de imagem mudam.

### 5. CLI de deploy: um único ponto de operação

Um CLI em Bash (`ops-deploy`) versionado no repositório de infraestrutura, instalado em `/usr/local/bin`, com subcomandos `deploy`, `rollback`, `status`, `verify` e `promote`. Ele encapsula: seleção de slot, atualização do serviço, espera de saúde, troca de rota, registro de release e validações de segurança (por exemplo, recusar imagem sem versão imutável).

**Por quê:** concentra a lógica crítica em um artefato testável e versionado, evita comandos longos e divergentes nos runbooks e dá à equipe um contrato estável.

**Alternativas consideradas:**

- **Scripts copiados em cada repositório:** divergem rapidamente.
- **Makefile no servidor:** difícil de versionar e testar; sem tratamento de erro consistente.

O CLI será coberto por testes automatizados (`bats` + `shellcheck`) e por um modo de simulação que valida a sequência de decisões sem tocar em produção.

### 6. Verificação de saúde: endpoint profundo no próprio container

Cada aplicação expõe `GET /health` (ou caminho equivalente documentado) retornando JSON com `status` e `checks`, e código 200 apenas quando as dependências obrigatórias respondem. O mesmo endpoint é usado pelo `HEALTHCHECK` do container, pelo CLI de deploy, pelo proxy e pelo monitoramento.

**Por quê:** uma única definição de saúde evita divergência entre deploy e operação, e testar dependências reais cumpre o requisito de "funcionando de verdade, não apenas processo vivo".

**Alternativas consideradas:**

- **Checagem apenas de porta/processo:** não detecta dependência indisponível nem aplicação travada.
- **Sonda externa separada:** duplicaria regras e poderia aprovar no deploy o que o monitoramento reprova.

### 7. Monitoramento e alertas: Uptime Kuma

Uptime Kuma executa verificações HTTP a cada 60 segundos contra o endpoint de saúde e a URL pública de cada aplicação, mantém painel de status e envia alertas por e-mail e/ou webhook, com repetição controlada.

**Por quê:** uma única ferramenta cobre disponibilidade, painel, canais de alerta e teste de notificação, com operação trivial para uma equipe pequena. O requisito é disponibilidade, não métricas de infraestrutura.

**Alternativas consideradas:**

- **Prometheus + Blackbox Exporter + Alertmanager + Grafana:** mais poderoso e mais peças para manter; o custo não se justifica nesta fase.
- **Alertas apenas no GitHub Actions:** não cobre indisponibilidade fora de uma execução de deploy.

Métricas de container (CPU, memória) ficam como evolução futura, fora do escopo.

### 8. Logs: Grafana Alloy + Loki + Grafana

Alloy coleta logs dos containers via socket do Docker, normaliza rótulos (`app`, `slot`, `version`, `service`) e envia ao Loki. Grafana é o ponto de consulta, já disponível para evoluir a painéis.

**Por quê:** stack open source consolidada, retenção configurável, consulta por rótulos e integração nativa com Docker. Alloy substitui o Promtail, que está em fim de vida.

**Alternativas consideradas:**

- **Elasticsearch + Kibana:** consumo de memória e complexidade operacional altos para o servidor.
- **Logs apenas no journald:** sem consulta centralizada por versão e sem correlação entre aplicações.
- **Serviço de logs pago:** vedado pela restrição de custo.

Contrato de log: aplicações escrevem JSON em stdout com `timestamp`, `level`, `message`, `request_id`, `version`; o proxy repassa/propaga `X-Request-ID` e as aplicações geram o identificador quando ausente.

### 9. Segredos: Docker Secrets + segredos do GitHub Actions

Segredos de aplicação ficam em Docker Secrets no Swarm (montados em tmpfs, com autolock habilitado). Credenciais de pipeline ficam nos segredos do GitHub. O repositório contém apenas `.env.example`.

**Por quê:** nativo, sem custo, sem serviço extra; atende injeção em tempo de execução e rotação com recriação controlada do serviço. O autolock criptografa o raft em repouso.

**Alternativas consideradas:**

- **SOPS + age no repositório:** bom para GitOps, mas exige divulgação de chave de descriptografia no CI.
- **HashiCorp Vault:** robusto, porém mais um serviço crítico para manter.

Rotação documentada: criar segredo com sufixo de versão, atualizar o serviço, validar saúde, remover o antigo.

### 10. Acesso e endurecimento do servidor

SSH apenas por chave, `PasswordAuthentication no`, `PermitRootLogin prohibit-password`, grupo `ops` para sudo, firewall permitindo somente 22/80/443, fail2ban, atualizações de segurança automáticas e auditoria básica (`auditd` ou journald persistente).

O usuário `deployer` do runner tem acesso ao socket Docker por necessidade de deploy; o risco é equivalente a root e será explicitado no runbook, com sudo restrito e sem login interativo.

**Alternativas consideradas:**

- **Docker rootless:** reduz o risco, mas complica Swarm, secrets e rede; inviável dentro do prazo e do perfil da equipe.
- **Runner em outra máquina:** elimina o risco local, mas não há outra máquina disponível.

### 11. Registro de releases e retenção

Cada deploy grava uma linha em `/var/lib/ops-deploy/releases.jsonl` com aplicação, versão, commit, slot, autor, horário, resultado e checksum da configuração. O CLI usa esse registro para `status` e para escolher a versão de rollback, mantendo as 5 últimas versões estáveis com imagem preservada no registro.

**Por quê:** histórico auditável independente do GitHub, consultável no servidor e suficiente para o procedimento de rollback documentado.

### 12. Ambiente de ensaio

Não haverá segundo servidor. O ensaio usa uma aplicação de referência (`demo-app`) e o slot inativo de uma aplicação de baixo risco, com hostname de teste, executando o mesmo pipeline e o mesmo CLI. Os ensaios de rollback e de runbook são feitos nesse contexto, em janela comunicada.

**Por quê:** permite provar o processo e treinar a equipe sem introduzir risco desnecessário em sistemas críticos.

## Architecture

```
                    Internet / rede interna
                              |
                        [ Traefik v3 ]
                     TLS ACME, rotas por host
                         /            \
              app-a-blue          app-b-green      (apenas um slot ativo por app)
                 |                      |
        +--------+--------+     +-------+--------+
        | Docker Swarm    |     |  volumes       |
        | (nó único)      |     |  persistentes  |
        +--------+--------+     +----------------+
                 |
     +-----------+------------+------------------+
     |                        |                  |
[ Uptime Kuma ]         [ Grafana + Loki ]   [ Docker Secrets ]
 alerta + painel        consulta de logs     segredos em runtime
                 |
        GitHub Actions runner (self-hosted)
                 |
        GitHub (código, imagens no GHCR)
```

## Risks / Trade-offs

- **[Servidor único é ponto único de falha]** → backups diários de volumes e configuração, imagem de reconstrução documentada, rollback testado; HA multi-host registrado como evolução.
- **[Runner com acesso ao socket Docker equivale a root]** → usuário sem login, sudo restrito, firewall de saída, segredos do GitHub com escopo mínimo, runbook de revogação.
- **[Blue-green dobra o consumo de recursos por aplicação]** → limite de CPU/memória por slot, janela curta de convivência e slot anterior encerrado após validação.
- **[Healthcheck profundo pode reprovar deploys por dependência instável]** → dependências obrigatórias separadas de opcionais no endpoint; timeouts e tentativas explícitos; logs do motivo da reprovação.
- **[Swarm em nó único tem recursos limitados de reconstrução]** → `releases.jsonl`, manifests versionados e runbook de recuperação do próprio Swarm.
- **[Migrations de banco fora do rollback automático]** → regra de compatibilidade retrospectiva (expand/contract) e passo de migração no runbook antes do deploy.
- **[Retenção de logs pode esgotar disco]** → limite de retenção e tamanho no Loki, alerta de uso de disco.
- **[Prazo de 2 semanas]** → escopo priorizado nos critérios de aceite; métricas de infraestrutura e tracing ficam para depois.

## Migration Plan

1. **Preparação:** inventário das aplicações, confirmação de DNS/domínio, acesso ao servidor e ao Git, definição do canal de alerta.
2. **Base:** endurecimento do servidor, Docker, Swarm, Traefik e certificados; implantação de uma aplicação piloto em paralelo ao processo manual, sem trocar o tráfego oficial.
3. **Pipeline:** ativação do runner, workflow de testes/build/scan e primeiro deploy blue-green da aplicação piloto.
4. **Observabilidade:** Uptime Kuma, Alloy/Loki/Grafana, alertas e painel.
5. **Segurança:** migração de segredos para Docker Secrets, remoção de credenciais do Git, restrição de acesso e revisão de permissões.
6. **Corte:** migração das demais aplicações uma a uma, com janela comunicada; desativação do processo manual ao final.
7. **Ensaio e entrega:** drill de deploy defeituoso, drill de rollback, validação dos runbooks por outro integrante, treinamento gravado.

**Rollback da própria entrega:** durante a migração, o processo manual anterior permanece disponível como contingência até a conclusão do drill e do aceite. A rota de cada aplicação pode ser revertida para o slot anterior pelo mesmo CLI.

## Open Questions

- Hospedagem Git definitiva (GitHub, GitLab ou Gitea): muda apenas o arquivo de pipeline e o registro de imagem; arquitetura e specs permanecem.
- Canal de alerta definitivo (SMTP próprio ou webhook para Teams/Slack): muda apenas a configuração do Uptime Kuma e o destinatário no runbook.
- Domínio e acesso ao DNS para TLS: pré-requisito de execução; pode ser um subdomínio interno com certificado da própria organização.
