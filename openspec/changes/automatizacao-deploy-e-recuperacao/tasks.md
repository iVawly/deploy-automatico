# Tasks

## 1. Descoberta e preparação

- [ ] 1.1 Levantar inventário das aplicações (repositório, linguagem, portas, dependências, dados persistentes, criticidade) em `docs/inventario.md` e conferir que cada aplicação aparece com dono e forma de execução definidos
- [ ] 1.2 Confirmar com o cliente a hospedagem Git efetiva e o canal de alerta; registrar a decisão no runbook e ajustar os nomes dos arquivos de pipeline e do canal de notificação conforme a escolha
- [ ] 1.3 Validar acesso ao servidor com chave SSH, acesso ao DNS e acesso administrativo aos repositórios; registrar evidência de cada acesso em `docs/acessos.md` sem incluir segredos
- [ ] 1.4 Criar os repositórios `infra` e de cada aplicação com estrutura inicial (`deploy/`, `dynamic/`, `scripts/`, `runbooks/`, `docs/`), commit inicial e branch protection na branch principal, verificando que push direto é bloqueado
- [ ] 1.5 Registrar a linha de base atual (versões em execução, portas, certificados, rotinas manuais) em `docs/estado-inicial.md` e validar que o restante do plano pode ser revertido para esse estado

## 2. Base do servidor, orquestração e proxy

- [ ] 2.1 Aplicar endurecimento SSH (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`, grupo `ops`) e validar que login por senha é recusado e que sudo é negado a usuário fora do grupo
- [ ] 2.2 Configurar firewall (22/80/443 apenas), fail2ban e atualizações de segurança automáticas; verificar com varredura de portas que nenhuma outra porta está exposta
- [ ] 2.3 Instalar Docker Engine e inicializar Swarm em nó único com autolock; verificar `docker info` e `docker node ls` com o nó `Ready`
- [ ] 2.4 Criar redes overlay (`public`, `internal`) e volumes persistentes por aplicação; verificar que um container de teste nas duas redes resolve o proxy e não expõe portas fora do proxy
- [ ] 2.5 Implantar Traefik v3 como serviço Swarm com TLS ACME e dashboard interno protegido; verificar emissão de certificado válido e que o dashboard exige autenticação
- [ ] 2.6 Configurar provider de arquivo do Traefik (`dynamic/`) e testar a troca a quente de uma rota de teste; verificar no log do Traefik que a nova rota é aplicada sem reinício
- [ ] 2.7 Documentar a reconstrução da base em `runbooks/reconstrucao-servidor.md` e verificar o documento executando os comandos em um servidor descartável ou no modo de simulação

## 3. CLI de deploy e estratégia blue-green

- [x] 3.1 Implementar `ops-deploy deploy <app> <versao>` com seleção de slot inativo, atualização do serviço, espera de saúde, troca de rota e registro em `releases.jsonl`; verificar com teste `bats` que cobre promoção bem-sucedida
- [x] 3.2 Implementar `ops-deploy verify <app>` com tempo limite de 5 segundos por verificação e saída legível por máquina; verificar testes de sucesso, falha de dependência e timeout
- [x] 3.3 Implementar `ops-deploy rollback <app> [versao]` preservando volumes e recusando versão inexistente; verificar teste que restaura a versão anterior e mantém o volume intacto
- [x] 3.4 Implementar `ops-deploy status <app>` lendo `releases.jsonl` e o estado do Swarm; verificar que exibe versão ativa, slot, data e resultado do último deploy
- [x] 3.5 Adicionar recusa de imagem sem tag imutável, validação de pré-condições (saúde do slot ativo antes de iniciar) e mensagens de erro com etapa e motivo; verificar com testes negativos
- [ ] 3.6 Configurar `shellcheck` e `bats` no CI do repositório `infra` e verificar que o pipeline falha quando um teste do CLI falha
- [ ] 3.7 Documentar o CLI em `docs/ops-deploy.md` com todos os subcomandos e exemplos, e validar que cada exemplo executa exatamente como escrito em ambiente de ensaio

## 4. Aplicação piloto e pipeline de entrega

- [ ] 4.1 Containerizar a aplicação piloto com Dockerfile multi-stage, usuário não root e `HEALTHCHECK` apontando para `/health`; verificar build local e container `healthy` com dependências disponíveis
- [x] 4.2 Implementar o endpoint `/health` profundo com `status`, `checks`, código 200/503 e versão em execução; verificar resposta correta com dependência simulada indisponível e disponível
- [x] 4.3 Padronizar logs estruturados em JSON com `timestamp`, `level`, `message`, `request_id` e `version`, gerando `request_id` quando ausente; verificar que duas requisições produzem identificadores distintos e correlacionáveis
- [ ] 4.4 Criar o workflow do repositório de aplicação com etapas de gitleaks, lint, testes, build, push para GHCR privado e chamada ao `ops-deploy`; verificar execução completa em um commit de teste
- [ ] 4.5 Instalar o runner auto-hospedado como serviço systemd sob o usuário `deployer` e registrar em `runbooks/runner.md`; verificar que o runner reconecta após reboot e que um job de teste consome o runner
- [ ] 4.6 Executar o primeiro deploy da aplicação piloto em paralelo ao processo manual, sem trocar o tráfego oficial; verificar que a versão nova responde no hostname de ensaio com saúde saudável
- [ ] 4.7 Provar o portão de testes e o portão de segredo: abrir PR com teste quebrado e outro com credencial fictícia; verificar que nenhum dos dois chega a implantar e que o motivo aparece no resumo do pipeline
- [ ] 4.8 Provar que versão doente não é promovida: gerar imagem com `/health` retornando 503; verificar que o tráfego permanece no slot anterior, que a release é marcada como reprovada e que o serviço continua disponível

## 5. Monitoramento, alertas e logs

- [ ] 5.1 Implantar Uptime Kuma em serviço Swarm com volume persistente, conta administrativa e canal de alerta configurado; verificar que o painel abre autenticado e que o teste de notificação é entregue
- [ ] 5.2 Cadastrar monitores HTTP a cada 60 segundos para URL pública e health endpoint de cada aplicação, com retentativa de 2 minutos e link para o runbook; verificar que a lista de monitores cobre todas as aplicações do inventário
- [ ] 5.3 Configurar notificação de recuperação e antiduplicação de alerta; verificar derrubando e restaurando uma aplicação de ensaio e conferindo exatamente um alerta e uma recuperação
- [ ] 5.4 Provar que o monitoramento sobrevive a deploy e a reinício de aplicação; verificar que as verificações continuam registradas durante um deploy da aplicação piloto
- [ ] 5.5 Implantar Grafana, Loki e Alloy com volume persistente, coleta por socket Docker e rótulos `app`, `slot`, `version`, `service`; verificar que os logs de uma aplicação aparecem no Grafana em até 30 segundos
- [ ] 5.6 Configurar retenção de 30 dias e limite de disco no Loki com alerta de uso; verificar a política por consulta de configuração e por simulação de rotação
- [ ] 5.7 Configurar o Traefik e as aplicações para propagar `X-Request-ID`; verificar a correlação de uma requisição entre proxy e aplicação pelos logs
- [ ] 5.8 Adicionar mascaramento de segredos nos logs (aplicação e pipeline) e verificar que uma execução com segredo fictício não expõe o valor no Loki nem no log do job
- [ ] 5.9 Documentar o uso do painel, consultas úteis e filtros em `docs/observabilidade.md`; verificar que um integrante localiza a causa de uma falha simulada seguindo apenas o documento

## 6. Segredos e controle de acesso

- [ ] 6.1 Criar os Docker Secrets por aplicação e ajustar os serviços para consumi-los em tempo de execução; verificar que a imagem publicada não contém os valores e que o serviço inicia com o segredo montado
- [ ] 6.2 Substituir arquivos de configuração sensíveis versionados por `.env.example` e remover credenciais do código e do histórico dos repositórios entregues; verificar com gitleaks que não há achados na branch principal
- [ ] 6.3 Configurar os segredos do GitHub com escopo mínimo e restringir o token do runner ao repositório e às ações necessárias; verificar que um comando fora do escopo é negado e registrado
- [ ] 6.4 Habilitar autolock do Swarm e documentar a chave de desbloqueio em local seguro fora do Git; verificar que o nó inicia bloqueado e exige desbloqueio conforme o runbook
- [ ] 6.5 Executar e documentar a rotação de um segredo de aplicação sem alterar código nem reconstruir imagem; verificar que a aplicação passa a usar o novo valor e mantém a mesma versão
- [ ] 6.6 Revisar usuários, chaves e grupos do servidor removendo acessos não necessários; verificar que uma chave revogada perde acesso e que o grupo `ops` contém apenas os responsáveis
- [ ] 6.7 Documentar política de segredos, acesso e revogação em `docs/seguranca.md`; verificar que a política responde aos requisitos de não exposição no Git e menor privilégio

## 7. Rollback, retenção e recuperação

- [x] 7.1 Registrar releases com versão, commit, slot, autor, horário, resultado e checksum em `releases.jsonl`; verificar que um deploy e um rollback geram registros distintos e auditáveis
- [x] 7.2 Garantir a retenção das 5 últimas versões estáveis por aplicação no registro e no GHCR; verificar que `status` lista as versões com data e saúde registrada
- [ ] 7.3 Executar drill de deploy defeituoso com rollback automático e medir o tempo de retorno; verificar que a versão estável anterior volta a atender e que o evento é registrado
- [ ] 7.4 Executar drill de rollback manual para uma versão anterior específica; verificar conclusão em até 5 minutos, saúde confirmada e volume de dados preservado
- [ ] 7.5 Testar falha durante o próprio rollback; verificar que a versão restaurada é mantida para diagnóstico e que um alerta crítico com link de runbook é emitido
- [ ] 7.6 Testar indisponibilidade de dependência externa e de disco cheio em ambiente de ensaio; verificar que o monitoramento alerta, os logs permitem identificar a causa e o servidor não perde o serviço ativo
- [ ] 7.7 Documentar a recuperação do Swarm e do servidor a partir dos manifests e do backup em `runbooks/recuperacao.md`; verificar o procedimento em servidor descartável

## 8. Migração das demais aplicações

- [ ] 8.1 Migrar a segunda aplicação (baixo risco) aplicando o mesmo checklist da piloto; verificar que health, logs, monitoramento e alerta estão funcionando antes de trocar o tráfego oficial
- [ ] 8.2 Migrar as aplicações restantes uma a uma, com janela comunicada e processo manual mantido como contingência; verificar por aplicação que deploy, monitor, logs e rollback foram exercitados
- [ ] 8.3 Remover a automação manual antiga e confirmar que todo deploy passa exclusivamente pelo pipeline; verificar que uma alteração aprovada chega a produção sem acesso manual ao servidor
- [ ] 8.4 Revisar inventário, runbooks e documentação após a migração; verificar que não restam referências a caminhos, portas ou processos antigos

## 9. Runbooks, treinamento e aceite

- [ ] 9.1 Escrever `runbooks/deploy.md`, `runbooks/rollback.md`, `runbooks/incidentes.md` e `runbooks/alertas.md` com comandos exatos, critérios de sucesso e escalonamento; verificar executando cada comando em ambiente de ensaio
- [ ] 9.2 Definir responsáveis por aplicação, canal de escalonamento e horários de atendimento em `docs/ownership.md`; verificar que cada alerta aponta para um responsável existente
- [ ] 9.3 Realizar validação dos runbooks por um integrante que não participou da implementação, executando deploy e rollback sem ajuda; registrar data, versões, tempo e problemas encontrados
- [ ] 9.4 Corrigir os problemas encontrados no ensaio e repetir a validação; verificar que o segundo integrante conclui o procedimento sem intervenção do autor
- [ ] 9.5 Gravar treinamento cobrindo pipeline, painel, alertas, logs, rollback e escalonamento; verificar que o vídeo e o material estão acessíveis à equipe e citados no índice de runbooks
- [ ] 9.6 Executar a demonstração de aceite: teste bloqueando deploy, versão defeituosa não promovida, alerta de indisponibilidade, causa identificada por log, rollback documentado e execução por outra pessoa; registrar evidências em `docs/aceite.md`
- [ ] 9.7 Entregar o pacote final (repositórios, backup das configurações, credenciais em local seguro, índice de documentação) e verificar que um integrante encontra cada item a partir do índice

## Cronograma (2 semanas)

- Dias 1–2: grupos 1 e 2 (inventário, base, Swarm, Traefik).
- Dias 3–5: grupos 3 e 4 (CLI, blue-green, runner, pipeline, aplicação piloto).
- Dias 6–7: grupo 5 (monitoramento, alertas, logs).
- Dia 8: grupo 6 (segredos e acesso).
- Dia 9: grupo 7 (rollback, drills e recuperação).
- Dia 10: grupo 8 (migração das demais aplicações e corte).
- Dias 11–12: grupo 9 (runbooks, validação por terceiro, treinamento e aceite).

## Workflow follow-up

- Arquive a mudança após a revisão e o aceite do cliente.
- Verifique o resultado arquivado e a atualização das specs principais.
