# Spec Delta

## Purpose

Assegurar que deploy, rollback e resposta a incidentes sejam executáveis por qualquer integrante treinado da equipe, com procedimentos versionados e validados por execução real.

## ADDED Requirements

### Requirement: Runbook de deploy
O sistema SHALL manter um runbook documentado e versionado que descreva como aprovar uma versão, acompanhar o pipeline, validar a implantação e comunicar a conclusão.

#### Scenario: Outro integrante acompanha um deploy
- **WHEN** um integrante que não desenvolveu a solução segue o runbook de deploy
- **THEN** consegue acompanhar a execução do pipeline e confirmar a versão em produção
- **AND** identifica o que fazer em caso de falha na execução

### Requirement: Runbook de rollback
O sistema SHALL manter um runbook documentado e versionado com o procedimento de rollback, incluindo comando de acionamento, verificação de saúde e critérios de encerramento.

#### Scenario: Rollback executado por terceiro
- **WHEN** um integrante que não desenvolveu a solução segue o runbook de rollback em um ambiente de ensaio
- **THEN** consegue restaurar a última versão estável sem ajuda do autor
- **AND** confirma a saúde do serviço após a restauração

### Requirement: Runbook de resposta a alertas e diagnóstico
O sistema SHALL manter um runbook que relacione cada alerta ao procedimento de diagnóstico correspondente, incluindo os filtros de log e os comandos de verificação de saúde a executar.

#### Scenario: Plantonista responde a um alerta
- **WHEN** um alerta de indisponibilidade é recebido
- **THEN** o plantonista consegue localizar o runbook indicado no alerta
- **AND** executa o diagnóstico inicial e determina a causa provável sem acessar cada aplicação individualmente

### Requirement: Validação dos runbooks por execução real
Cada runbook crítico SHALL ser validado por um integrante diferente do autor, executando o procedimento em ambiente de ensaio ou em janela controlada de produção, com o resultado registrado.

#### Scenario: Validação registrada do runbook de rollback
- **WHEN** a validação do runbook de rollback é concluída
- **THEN** existe um registro com data, responsável pela execução, versões envolvidas e tempo total do procedimento
- **AND** os problemas encontrados foram corrigidos no runbook

#### Scenario: Runbook desatualizado é detectado
- **WHEN** o processo automatizado muda de forma que invalide um comando do runbook
- **THEN** a alteração do processo inclui a atualização do runbook correspondente na mesma entrega

### Requirement: Documentação de propriedade e escalonamento
O sistema SHALL documentar quem são os responsáveis pela operação de cada aplicação, o canal de escalonamento e os horários de atendimento.

#### Scenario: Escalonamento identificado
- **WHEN** um incidente não é resolvido pelo primeiro responsável
- **THEN** o runbook indica quem acionar em seguida e por qual canal
