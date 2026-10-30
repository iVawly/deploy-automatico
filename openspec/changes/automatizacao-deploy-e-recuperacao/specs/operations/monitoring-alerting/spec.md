# Spec Delta

## Purpose

Permitir que a equipe perceba rapidamente quando um serviço deixa de responder, veja o estado consolidado das aplicações e receba alertas acionáveis sem depender de chamados de usuários.

## ADDED Requirements

### Requirement: Verificação contínua de disponibilidade
O sistema SHALL verificar a disponibilidade de cada aplicação em intervalos regulares não superiores a 1 minuto, independentemente da versão implantada ou de uma execução de deploy em andamento.

#### Scenario: Verificação ocorre sem interrupção durante deploy
- **WHEN** um deploy está em andamento
- **THEN** as verificações de disponibilidade das aplicações continuam sendo executadas
- **AND** uma queda real do serviço é detectada durante o deploy

#### Scenario: Monitoramento sobrevive a falha de aplicação
- **WHEN** um container de aplicação é encerrado ou reiniciado
- **THEN** o monitoramento continua ativo e registra a indisponibilidade

### Requirement: Painel consolidado de disponibilidade
O sistema SHALL disponibilizar um painel único com o estado atual de cada aplicação, a versão em execução, o tempo desde a última verificação e o histórico de disponibilidade.

#### Scenario: Visualização do estado de todos os serviços
- **WHEN** um membro da equipe abre o painel
- **THEN** consegue identificar quais aplicações estão disponíveis, degradadas ou indisponíveis
- **AND** visualiza a versão em execução e o horário da última verificação de cada aplicação

### Requirement: Alerta quando serviço fica indisponível
O sistema SHALL emitir um alerta para o canal configurado pela equipe quando uma aplicação falhar em verificações consecutivas por um período igual ou superior a 2 minutos.

#### Scenario: Indisponibilidade gera alerta
- **WHEN** uma aplicação falha em todas as verificações por 2 minutos consecutivos
- **THEN** um alerta é enviado ao canal configurado
- **AND** o alerta informa aplicação, versão, horário de início e link para o runbook de resposta

#### Scenario: Falha isolada não gera alerta
- **WHEN** uma única verificação falha e a verificação seguinte retorna sucesso
- **THEN** nenhum alerta de indisponibilidade é emitido

#### Scenario: Alerta não é duplicado indefinidamente
- **WHEN** uma aplicação permanece indisponível após o primeiro alerta
- **THEN** o sistema não envia um novo alerta a cada verificação
- **AND** registra a persistência da indisponibilidade no painel

### Requirement: Notificação de recuperação
O sistema SHALL enviar uma notificação de recuperação quando uma aplicação que estava em alerta voltar a responder de forma saudável.

#### Scenario: Serviço recuperado encerra o alerta
- **WHEN** a aplicação volta a ser considerada saudável
- **THEN** uma notificação de recuperação é enviada ao mesmo canal
- **AND** o painel passa a exibir o serviço como disponível

### Requirement: Alerta com informação suficiente para ação
Todo alerta SHALL incluir identificação da aplicação afetada, horário da detecção, versão em execução e referência ao procedimento de diagnóstico correspondente.

#### Scenario: Plantonista identifica o que fazer
- **WHEN** um alerta é recebido
- **THEN** o destinatário consegue identificar a aplicação, a versão e o runbook aplicável sem consultar outra fonte

### Requirement: Canal de alerta configurável e testável
O sistema SHALL permitir configurar ao menos um canal de alerta por e-mail ou webhook e SHALL oferecer um teste de envio que não dependa de derrubar uma aplicação real.

#### Scenario: Teste de canal de alerta
- **WHEN** a equipe solicita um alerta de teste
- **THEN** uma mensagem de teste é entregue ao canal configurado
- **AND** o resultado da entrega é exibido para a equipe
