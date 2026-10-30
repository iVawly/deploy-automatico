# Proposal

## Why

As aplicações internas da empresa são atualizadas manualmente por um único membro da equipe de TI em um servidor Ubuntu, sem testes obrigatórios, verificação de saúde ou caminho de retorno. O histórico recente já registra indisponibilidade causada por deploy defeituoso, dependências desatualizadas e serviços fora do ar descobertos apenas por chamado de usuário. O objetivo é substituir esse processo por um fluxo de entrega seguro, observável, recuperável e documentado, sem contratar plataforma paga e sem depender de uma única pessoa.

## What Changes

- Pipeline de integração e entrega contínua que, a cada versão aprovada no Git, executa testes automatizados, constrói a imagem e só implanta se todas as etapas passarem.
- Implantação em containers Docker com versionamento imutável e troca controlada de tráfego, de modo que uma versão doente nunca substitua silenciosamente uma versão saudável.
- Verificação de saúde profunda (dependências reais, não apenas processo vivo) antes e depois de cada implantação, com bloqueio automático da promoção em caso de falha.
- Rollback com um único comando para a última versão estável conhecida, usando artefatos já construídos, sem reconstrução manual.
- Monitoramento de disponibilidade por serviço, painel único e envio de alertas quando um serviço deixar de responder.
- Centralização de logs de aplicação e do pipeline em um ponto único de consulta, com correlação por versão e serviço.
- Gestão de credenciais e chaves fora do repositório Git, com acesso ao servidor controlado por chave e menor privilégio.
- Runbooks operacionais e um treinamento prático gravado, validados por outra pessoa da equipe executando deploy e rollback sem ajuda do autor.

## Capabilities

### New Capabilities

- `continuous-delivery/automated-deploy`: pipeline que testa, constrói e implanta automaticamente cada versão aprovada, com portões de qualidade e implantação sem parada total dos sistemas.
- `continuous-delivery/deployment-safety`: versionamento imutável das releases, promoção condicionada à saúde e rollback para a última versão estável sem reconstrução.
- `operations/health-checks`: endpoints e sondas de saúde que atestam funcionamento real, incluindo dependências, usados no deploy e na operação contínua.
- `operations/monitoring-alerting`: verificação contínua de disponibilidade, painel de status e alertas acionáveis quando um serviço fica indisponível.
- `operations/log-aggregation`: coleta e consulta centralizada de logs de aplicação, proxy e pipeline, com correlação por serviço, versão e requisição.
- `security/secrets-and-access`: segredos fora do Git, injeção em tempo de execução e controle de acesso ao servidor e ao pipeline.
- `operations/runbooks`: procedimentos documentados de deploy, rollback, diagnóstico e resposta a alertas, comprovadamente executáveis por outro membro da equipe.

### Modified Capabilities

Nenhuma. O projeto não possui specs existentes.

## Impact

- **Infraestrutura**: único servidor Ubuntu Server 24.04 passará a executar Docker Engine, runner de CI, reverse proxy, stack de monitoramento e agregação de logs.
- **Aplicações**: cada aplicação precisa ser containerizável, expor endpoint de saúde e publicar logs em stdout/stderr; aplicações sem Dockerfile recebem um na fase de onboarding.
- **Repositórios Git**: novo arquivo de pipeline, Dockerfiles e configuração de ambientes; segredos passam a ser configurados no cofre do CI, nunca versionados.
- **Processo da equipe**: deploy deixa de ser manual e passa a ser disparado por tag/merge aprovado; rollback e resposta a alertas seguem runbooks.
- **Dependências**: componentes open source auto-hospedados (Docker, reverse proxy, monitoramento, logs, alertas), sem licenças pagas.
- **Premissas registradas**: hospedagem Git compatível com GitHub Actions (adaptável a GitLab CI com o mesmo desenho); 1 a 5 aplicações Docker no mesmo servidor; alertas por e-mail e/ou webhook; janela de implantação sem parada total, aceitando indisponibilidade breve por serviço durante a troca.
- **Fora de escopo**: alta disponibilidade multi-servidor, Kubernetes, contratação de SaaS de observabilidade, migração de dados das aplicações e reescrita de aplicações.
