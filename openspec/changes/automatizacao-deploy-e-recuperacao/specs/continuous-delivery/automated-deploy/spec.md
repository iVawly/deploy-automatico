# Spec Delta

## Purpose

Define como uma versão aprovada no repositório Git é testada, empacotada e implantada de forma automatizada, repetível e sem depender de execução manual no servidor.

## ADDED Requirements

### Requirement: Deploy disparado por versão aprovada
O sistema SHALL iniciar o pipeline de entrega somente a partir de uma versão aprovada no repositório Git, identificada por tag de release ou merge aprovado na branch principal.

#### Scenario: Versão aprovada dispara o pipeline
- **WHEN** uma tag de release é criada sobre um commit aprovado na branch principal
- **THEN** o pipeline é iniciado automaticamente para essa versão
- **AND** a execução é associada ao identificador da versão e ao hash do commit

#### Scenario: Commit não aprovado não é implantado
- **WHEN** um commit é enviado a uma branch de trabalho sem tag de release e sem merge aprovado
- **THEN** nenhuma implantação em produção é executada

### Requirement: Testes obrigatórios antes da implantação
O pipeline SHALL executar a suíte de testes automatizados da aplicação e SHALL interromper o fluxo antes da construção do artefato ou da implantação quando qualquer teste falhar.

#### Scenario: Testes com falha bloqueiam o deploy
- **WHEN** ao menos um teste automatizado falha
- **THEN** o pipeline é encerrado com status de falha
- **AND** nenhuma nova versão é implantada no servidor
- **AND** a versão saudável em execução permanece inalterada

#### Scenario: Testes aprovados liberam a construção
- **WHEN** todos os testes automatizados passam
- **THEN** o pipeline prossegue para a construção do artefato da versão

### Requirement: Artefato imutável e identificável
O pipeline SHALL construir uma imagem de container imutável identificada pela versão e pelo hash do commit, e SHALL publicá-la em um registro acessível apenas pela infraestrutura da empresa.

#### Scenario: Imagem publicada com identificação da versão
- **WHEN** a construção da imagem termina com sucesso
- **THEN** a imagem é publicada com uma referência que contém a versão e o hash do commit
- **AND** a mesma referência é registrada no histórico da execução do pipeline

#### Scenario: Mesma versão reutiliza o mesmo artefato
- **WHEN** um rollback ou uma reimplantação da mesma versão é solicitado
- **THEN** o sistema usa a imagem já publicada para aquela versão
- **AND** não reconstrói a imagem a partir do código-fonte

### Requirement: Implantação sem desligamento total dos sistemas
O processo de implantação SHALL substituir as instâncias de cada aplicação de forma controlada, mantendo as demais aplicações disponíveis e evitando interrupção de todas as aplicações ao mesmo tempo.

#### Scenario: Deploy de uma aplicação mantém as demais ativas
- **WHEN** uma nova versão de uma aplicação é implantada
- **THEN** as outras aplicações continuam respondendo durante o processo
- **AND** a troca de tráfego da aplicação ocorre sem interromper todas as suas instâncias simultaneamente

### Requirement: Falha de deploy não derruba a versão atual
O pipeline SHALL tratar qualquer erro de construção, publicação ou implantação como falha da release, preservando em execução a última versão saudável.

#### Scenario: Erro durante o deploy preserva o serviço
- **WHEN** a implantação de uma nova versão falha em qualquer etapa
- **THEN** a versão anterior continua atendendo o tráfego
- **AND** a execução do pipeline é marcada como falha
- **AND** a equipe responsável é notificada com a etapa e o motivo da falha

### Requirement: Registro auditável das execuções
O sistema SHALL manter o histórico de cada execução do pipeline com versão, commit, autor, etapas, duração e resultado por pelo menos 90 dias.

#### Scenario: Consulta ao histórico de deploys
- **WHEN** um membro da equipe consulta o histórico de uma aplicação
- **THEN** consegue identificar qual versão está em produção, quando foi implantada e qual foi o resultado da execução
