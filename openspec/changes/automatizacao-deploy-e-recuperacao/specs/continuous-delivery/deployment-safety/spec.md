# Spec Delta

## Purpose

Garantir que uma versão só receba tráfego após comprovar saúde e que o retorno à última versão estável seja rápido, previsível e executável por qualquer membro da equipe.

## ADDED Requirements

### Requirement: Promoção condicionada à verificação de saúde
O sistema SHALL liberar tráfego para uma nova versão somente após a verificação de saúde pós-implantação confirmar que a aplicação e suas dependências obrigatórias estão operacionais.

#### Scenario: Versão saudável é promovida
- **WHEN** a nova versão inicia, responde ao endpoint de saúde com estado saudável e permanece estável durante o período de observação
- **THEN** o tráfego é direcionado integralmente para a nova versão
- **AND** a versão é registrada como a última versão estável

#### Scenario: Versão doente não recebe tráfego
- **WHEN** a nova versão falha na verificação de saúde ou não responde dentro do tempo limite
- **THEN** o tráfego não é direcionado para ela
- **AND** a versão anterior continua atendendo normalmente

### Requirement: Versão defeituosa não substitui silenciosamente a saudável
O sistema SHALL manter a última versão estável em execução até que a nova versão seja considerada saudável, e SHALL marcar como reprovada qualquer versão que falhe na promoção.

#### Scenario: Deploy defeituoso é revertido automaticamente
- **WHEN** a verificação de saúde pós-implantação falha
- **THEN** o sistema desfaz a promoção sem intervenção manual
- **AND** a versão reprovada é registrada como não utilizável para produção

#### Scenario: Reprovação não altera a versão em produção
- **WHEN** uma versão é marcada como reprovada
- **THEN** a versão estável anterior permanece em execução e identificada como atual

### Requirement: Rollback para a última versão estável
O sistema SHALL permitir reverter uma aplicação para a última versão estável anterior por meio de um único comando ou de um procedimento documentado, sem reconstruir a imagem e sem editar manualmente arquivos no servidor.

#### Scenario: Rollback bem-sucedido
- **WHEN** a equipe aciona o rollback de uma aplicação
- **THEN** a versão estável anterior volta a atender todo o tráfego
- **AND** a operação é concluída em até 5 minutos a partir do acionamento
- **AND** o evento é registrado no histórico com autor, versão de origem e versão de destino

#### Scenario: Rollback verificado
- **WHEN** a versão anterior é restaurada
- **THEN** o sistema executa a verificação de saúde da versão restaurada
- **AND** confirma no histórico que o serviço está saudável na versão restaurada

#### Scenario: Rollback falha
- **WHEN** a verificação de saúde falha após o rollback
- **THEN** o sistema mantém a versão restaurada para diagnóstico, não a descarta automaticamente
- **AND** emite alerta crítico com o serviço afetado e o link para o runbook de incidente

### Requirement: Retenção de versões anteriores
O sistema SHALL manter disponíveis as imagens e configurações das últimas versões estáveis de cada aplicação, em quantidade suficiente para permitir rollback imediato.

#### Scenario: Versões anteriores disponíveis para reversão
- **WHEN** a equipe lista as versões de uma aplicação
- **THEN** ao menos as 5 últimas versões estáveis estão disponíveis para rollback
- **AND** cada versão exibe data de implantação e status de saúde registrado

### Requirement: Reversão sem perda de estado persistente
O procedimento de rollback SHALL preservar os dados persistentes da aplicação, revertendo apenas a versão do código e sua configuração.

#### Scenario: Dados persistentes preservados no rollback
- **WHEN** um rollback é executado
- **THEN** volumes e dados persistentes da aplicação não são apagados nem recriados
- **AND** a aplicação restaurada acessa os mesmos dados que utilizava antes da atualização
