# Spec Delta

## Purpose

Manter credenciais fora do repositório Git e restringir o acesso ao servidor e ao pipeline às pessoas e automações que realmente precisam dele.

## ADDED Requirements

### Requirement: Nenhuma credencial no repositório Git
Os repositórios de aplicação e de infraestrutura SHALL NOT conter senhas, tokens, chaves privadas ou certificados com chave privada, nem em arquivos versionados nem no histórico entregue à equipe.

#### Scenario: Verificação automática de segredos no pipeline
- **WHEN** um commit contendo um padrão de credencial conhecida é enviado ao repositório
- **THEN** o pipeline sinaliza o achado e interrompe a promoção da versão
- **AND** a mensagem indica o arquivo e o tipo de credencial detectada, sem exibir o valor

#### Scenario: Configuração local sem segredos versionados
- **WHEN** uma aplicação precisa de configuração sensível para executar
- **THEN** o repositório contém apenas um modelo de variáveis sem valores reais
- **AND** os valores reais são fornecidos pelo ambiente de execução

### Requirement: Segredos injetados em tempo de execução
O sistema SHALL fornecer segredos às aplicações em tempo de execução, a partir de um armazenamento de segredos, sem embuti-los na imagem ou no código-fonte.

#### Scenario: Container recebe segredo sem embutir na imagem
- **WHEN** uma aplicação é iniciada
- **THEN** ela recebe os segredos necessários por variável de ambiente ou arquivo montado
- **AND** a imagem publicada não contém o valor do segredo

#### Scenario: Segredo não aparece em inspeção comum do container
- **WHEN** o container em execução é inspecionado por um usuário sem permissão de leitura de segredos
- **THEN** os valores dos segredos não são exibidos

### Requirement: Acesso ao servidor por chave e menor privilégio
O servidor SHALL aceitar acesso administrativo apenas por chave SSH, com autenticação por senha desabilitada, e SHALL limitar privilégios elevados aos membros do grupo de operações.

#### Scenario: Senha SSH rejeitada
- **WHEN** uma tentativa de acesso SSH por senha é realizada
- **THEN** o servidor recusa a autenticação
- **AND** a tentativa é registrada no log de autenticação

#### Scenario: Usuário sem grupo de operações não eleva privilégio
- **WHEN** um usuário autenticado sem participação no grupo de operações tenta executar comando administrativo
- **THEN** a elevação de privilégio é negada

#### Scenario: Chave revogada perde acesso
- **WHEN** a chave de um integrante é removida do servidor
- **THEN** novas conexões com essa chave são recusadas

### Requirement: Credencial de automação com escopo mínimo
A credencial usada pelo pipeline SHALL ter permissão apenas para publicar artefatos e executar o deploy das aplicações previstas, sem acesso administrativo irrestrito ao servidor.

#### Scenario: Pipeline não executa ação fora do escopo
- **WHEN** o pipeline tenta uma operação não prevista, como alterar configuração de firewall
- **THEN** a operação é negada
- **AND** a tentativa é registrada no log de auditoria

### Requirement: Rotação de credenciais sem alteração de código
O sistema SHALL permitir substituir um segredo utilizado em produção sem alterar o código-fonte ou reconstruir a imagem, exigindo apenas a atualização no armazenamento de segredos e a reinicialização controlada do serviço.

#### Scenario: Rotação aplicada a uma aplicação
- **WHEN** a equipe atualiza o valor de um segredo no armazenamento e reinicia a aplicação de forma controlada
- **THEN** a aplicação passa a usar o novo valor
- **AND** a versão do código permanece a mesma
