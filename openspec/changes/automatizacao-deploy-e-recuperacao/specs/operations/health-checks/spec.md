# Spec Delta

## Purpose

Definir uma verificação de saúde padronizada que comprove o funcionamento real de cada aplicação, incluindo dependências, e que sirva tanto para o deploy quanto para o monitoramento contínuo.

## ADDED Requirements

### Requirement: Endpoint de saúde por aplicação
Cada aplicação SHALL expor um endpoint HTTP de saúde que retorne um estado legível por máquina e não exija autenticação de usuário final.

#### Scenario: Aplicação saudável responde com sucesso
- **WHEN** o endpoint de saúde é consultado e a aplicação e suas dependências obrigatórias estão operacionais
- **THEN** a resposta tem código HTTP 200 e indica estado saudável
- **AND** a resposta identifica a versão em execução

#### Scenario: Aplicação doente responde com falha
- **WHEN** uma dependência obrigatória está indisponível ou a aplicação não consegue processar requisições
- **THEN** a resposta tem código HTTP de erro ou indica estado não saudável
- **AND** a resposta identifica qual dependência falhou

### Requirement: Verificação de dependências reais
A verificação de saúde SHALL testar as dependências obrigatórias da aplicação, e não apenas a existência do processo ou da porta.

#### Scenario: Dependência indisponível reprova a saúde
- **WHEN** o banco de dados, cache ou serviço externo obrigatório não responde dentro do tempo limite
- **THEN** a verificação de saúde reprova a aplicação
- **AND** o relatório aponta a dependência que falhou e o tempo de resposta excedido

#### Scenario: Processo vivo com aplicação travada é reprovado
- **WHEN** o processo da aplicação continua em execução mas não responde a requisições dentro do tempo limite
- **THEN** a verificação de saúde reprova a aplicação

### Requirement: Tempo limite e isolamento da verificação
A verificação de saúde SHALL possuir tempo limite máximo de 5 segundos por aplicação e SHALL ser executada de forma independente do ciclo de vida do container verificado.

#### Scenario: Verificação não trava indefinidamente
- **WHEN** uma aplicação não responde
- **THEN** a verificação termina em no máximo 5 segundos com estado não saudável
- **AND** as verificações das demais aplicações seguem normalmente

### Requirement: Endpoint de saúde com acesso restrito
O endpoint de saúde SHALL ser acessível apenas pela rede interna e pela infraestrutura de monitoramento, não pela rede pública.

#### Scenario: Acesso externo bloqueado
- **WHEN** o endpoint de saúde é acessado pela rede pública
- **THEN** a requisição é recusada
- **AND** o detalhamento interno de dependências não é exposto publicamente

### Requirement: Definição única de saúde entre deploy e monitoramento
O deploy e o monitoramento contínuo SHALL usar a mesma definição de saúde e os mesmos limites de tempo para uma determinada aplicação.

#### Scenario: Reprovação consistente entre deploy e monitoramento
- **WHEN** uma aplicação é considerada não saudável pelo monitoramento contínuo
- **THEN** a mesma condição seria considerada não saudável pelo portão de saúde do deploy
