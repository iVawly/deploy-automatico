# Spec Delta

## Purpose

Centralizar logs de aplicações, proxy e pipeline em um ponto único de consulta para que uma falha possa ser investigada sem acessar cada aplicação individualmente.

## ADDED Requirements

### Requirement: Coleta centralizada de logs
O sistema SHALL coletar logs das aplicações, do reverse proxy e das execuções do pipeline em um armazenamento central consultável.

#### Scenario: Log de aplicação disponível no ponto central
- **WHEN** uma aplicação registra uma mensagem em stdout ou stderr
- **THEN** a mensagem fica consultável no armazenamento central em até 30 segundos
- **AND** o registro contém aplicação, versão, container e horário

#### Scenario: Logs sobrevivem à recriação do container
- **WHEN** um container é recriado por deploy ou rollback
- **THEN** os logs anteriores permanecem disponíveis para consulta

### Requirement: Consulta por serviço, período e versão
O sistema SHALL permitir filtrar logs por aplicação, intervalo de tempo e versão em execução.

#### Scenario: Investigação de falha por versão
- **WHEN** um membro da equipe filtra os logs de uma aplicação pela versão que apresentou falha
- **THEN** recebe apenas os registros daquela aplicação naquela versão e período

### Requirement: Correlação de requisição
Os logs de aplicação e de proxy SHALL incluir um identificador de correlação que permita acompanhar uma mesma requisição entre os componentes.

#### Scenario: Rastreamento de uma requisição que falhou
- **WHEN** o identificador de correlação de uma requisição com erro é pesquisado
- **THEN** os logs do proxy e da aplicação referentes àquela requisição são apresentados em ordem cronológica

#### Scenario: Identificador ausente não impede a consulta
- **WHEN** uma entrada de log não possui identificador de correlação
- **THEN** ela continua consultável pelos demais filtros

### Requirement: Retenção de logs para investigação
O sistema SHALL reter logs por no mínimo 30 dias e SHALL remover registros mais antigos de forma automática.

#### Scenario: Consulta dentro do período de retenção
- **WHEN** um incidente ocorrido há 20 dias é investigado
- **THEN** os logs correspondentes estão disponíveis
- **AND** logs com mais de 30 dias já foram removidos automaticamente

#### Scenario: Retenção não esgota o disco do servidor
- **WHEN** o volume de logs cresce além do limite configurado
- **THEN** o sistema aplica a política de retenção e rotação definida
- **AND** o servidor continua operando dentro dos limites de disco

### Requirement: Logs sem credenciais expostas
O sistema SHALL impedir que senhas, tokens e chaves apareçam nos logs centralizados.

#### Scenario: Valor sensível não aparece no log
- **WHEN** uma aplicação ou o pipeline manipula um segredo configurado
- **THEN** o valor do segredo não é exibido nos logs centralizados
- **AND** o registro indica apenas que o valor foi omitido
