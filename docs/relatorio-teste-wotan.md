# Relatório do teste real de deploy com site institucional

## Resumo

Este relatório descreve o teste de ponta a ponta feito com o `ops-deploy` usando
uma aplicação real: o site estático do Wotan. O objetivo foi validar o fluxo
completo em um Docker Engine Linux com Swarm, e não apenas os testes com dublês.

Resultado: o fluxo principal passou. Bootstrap, deploy saudável, verificação
pública, recusa de deploy quebrado, rollback, recover, verify e status
funcionaram. Dois bugs do CLI apareceram durante o teste e foram corrigidos.
A validação não foi feita em um host Ubuntu real; as limitações estão listadas
no fim do documento.

## Objetivo

Validar o comportamento do CLI e da stack local com uma aplicação de verdade,
cobrindo:

- criação da imagem e publicação em registry;
- bootstrap do primeiro slot;
- deploy blue-green com troca de tráfego;
- health check antes da promoção;
- verificação pública pela rota do Traefik;
- recusa de versão defeituosa;
- rollback, recover, verify e status;
- registro no ledger e leitura do estado atual.

## Ambiente

- Windows com Docker Desktop.
- Docker Engine `29.8.1` em uma VM Linux do Docker Desktop.
- Swarm ativo em nó único.
- Stack local `demo-platform`.
- Traefik como proxy de entrada.
- Registry local em `127.0.0.1:5000`.
- Git Bash como shell de execução.
- Domínio de teste: `wotan.127.0.0.1.nip.io`.
- TLS self-signed, com verificação insegura habilitada apenas no demo.

O Docker Desktop não é um simulador de containers: os containers, o Swarm e o
Docker Engine rodam em Linux de verdade. A diferença em relação a um servidor
Ubuntu está na camada de host: bind mount, file watcher, rede, systemd e
permissões do sistema.

## Aplicação de teste

O site estava em `C:\Users\Alexandre\wotan`, com HTML, CSS e JavaScript
estáticos e sem etapa de build própria.

Para transformar o site em uma aplicação deployável:

1. O conteúdo foi copiado para um diretório temporário de build.
2. Foi criado um `Dockerfile` baseado em
   `nginxinc/nginx-unprivileged:1.29-alpine`.
3. Foi criado um `nginx.conf` com o endpoint `/health`.
4. O health passou a devolver JSON no contrato esperado pelo CLI:

   ```json
   {"status":"healthy","service":"wotan-house","version":"1.0.2"}
   ```

5. O app foi configurado em `local-demo/apps/wotan/app.conf` com domínio,
   porta, imagem, rootfs read-only, `cap-drop ALL` e limites de recursos.

As imagens foram publicadas no registry local com tags imutáveis e digests
registrados no ledger.

## Roteiro executado

### 1. Bootstrap da versão 1.0.0

A primeira versão foi publicada e o slot `blue` foi criado pelo comando de
bootstrap.

Nessa etapa, o Traefik do Docker Desktop não recarregou automaticamente a rota
gravada em `dynamic/`, então a verificação pública foi desabilitada com
`APP_VERIFY_PUBLIC=0`. A rota foi validada depois de um reload manual do
Traefik.

### 2. Deploy da versão 1.0.1

O título do site foi alterado para `v1.0.1`, uma nova imagem foi publicada e o
deploy foi executado pelo CLI.

O fluxo observado foi:

1. O CLI identificou o slot ativo (`blue`).
2. Criou o candidato no slot inativo (`green`).
3. Aguardou o health check do candidato.
4. Trocou a rota do Traefik para o candidato.
5. Manteve o slot anterior como fallback.

Depois de forçar o reload do Traefik no Windows, o título `v1.0.1` foi
confirmado publicamente.

### 3. Deploy da versão 1.0.2

O mesmo procedimento foi repetido com o título `v1.0.2`. Dessa vez, a
verificação pública automática foi exercitada com mais tentativas e um watcher
temporário que forçava o reload do Traefik quando a rota era atualizada.

O deploy passou, a `1.0.2` ficou ativa no slot `blue` e a página pública passou
a responder com `Wotan's House v1.0.2`.

### 4. Deploy da versão 2.0.0 com defeito

A primeira tentativa de criar uma imagem defeituosa não funcionou como
esperado. O `index.html` padrão da imagem base continuou presente, então a
aplicação ainda respondia e o deploy foi aceito. O caso foi corrigido com um
rollback para a `1.0.1`.

Depois, a imagem foi reconstruída removendo explicitamente o arquivo padrão:

```dockerfile
RUN rm -f /usr/share/nginx/html/index.html
```

Com isso, o `/health` passou a retornar `503`. Ao executar o deploy, o CLI
recusou a versão antes de trocar o tráfego:

```text
health check reprovado antes da troca de tráfego
```

A versão ativa foi preservada. Esse é o comportamento esperado para impedir que
uma versão defeituosa substitua a estável.

### 5. Rollback

O rollback da `2.0.0` para a `1.0.1` foi executado pelo CLI. A versão anterior
foi restaurada, a rota foi atualizada e o evento ficou registrado no ledger.

### 6. Recover

O slot ativo foi escalado para zero para simular a perda do serviço. Em
seguida, o comando de recover recriou o serviço a partir do ledger.

O health voltou a responder corretamente na versão registrada como ativa.

### 7. Verify e status

O `verify` consultou o health do slot ativo e devolveu JSON válido com
`healthy: true` e a versão em execução.

O `status` mostrou versão ativa, slot, digest, versões estáveis, últimas
releases e os serviços da aplicação.

## Resultados por versão

| Versão | Cenário | Resultado |
|---|---|---|
| 1.0.0 | Bootstrap inicial | Slot `blue` criado; rota validada após reload do Traefik |
| 1.0.1 | Deploy saudável | Aceito; tráfego trocado para o candidato |
| 1.0.2 | Deploy saudável com verificação pública | Aceito; página pública confirmou a versão |
| 2.0.0 (primeira) | Falso positivo do teste | Aceito porque o `index.html` padrão ainda existia; rollback executado |
| 2.0.0 (corrigida) | Health retornando 503 | Recusado antes da troca; versão ativa preservada |
| 1.0.1 | Rollback | Versão restaurada e registrada no ledger |
| 1.0.2 | Recover | Serviço recriado a partir do ledger e saudável |

## Bugs encontrados e correções

### `--security-opt` incompatível com o Docker 29.8.1

O `docker service create` dessa versão retornava:

```text
unknown flag: --security-opt
```

O CLI adicionava `--security-opt no-new-privileges:true` de forma
incondicional, o que quebrava o bootstrap e o deploy.

Correção aplicada:

- criação do helper `security_opt_supported()`;
- verificação de suporte com `docker service create --help`;
- aplicação condicional da flag;
- aviso quando o Docker não suporta a opção;
- teste Bats cobrindo o caminho de fallback.

### Seção de serviços vazia no `status`

O `status` usava `docker service ps` sem informar um serviço. O Docker retornava
erro de argumento obrigatório e a seção `serviços:` ficava vazia.

Correção aplicada: uso de `docker service ls` com filtro por label
`opsdeploy_app=<app>`.

### Traefik sem recarregar a rota no Windows

O Traefik não detectava arquivos novos ou alterados em `dynamic/` quando o
diretório era um bind mount do Docker Desktop. A verificação pública falhava
com `404` até o serviço do Traefik ser forçado a recarregar.

Esse ponto é uma limitação do ambiente Windows, não do CLI. O contorno usado
foi:

```bash
docker service update --force demo-platform_traefik
```

Em um host Linux real, o file watcher deve funcionar sem esse contorno, mas isso
não foi validado neste teste.

### Falso positivo da imagem 2.0.0

A primeira imagem defeituosa não estava realmente defeituosa. O problema era do
teste, não do deploy. A remoção explícita do `index.html` padrão corrigiu o
cenário e permitiu validar a recusa.

## Testes automatizados

- Bats: `41/41` passando em container Linux com Python e GNU tar.
- Testes Python do `demo-app`: `10/10`.
- ShellCheck: sem achados em `scripts/ops-deploy` e `tests/shims/docker`.
- Um teste do Bats foi pulado no container por falta de GNU `timeout`.

A suíte Bats executada diretamente no Git Bash do Windows apresentou
travamentos intermitentes. A execução em container Linux foi usada como
referência.

## O que foi validado

- O CLI conduz o fluxo blue-green sem intervenção manual nos serviços.
- O health check bloqueia a promoção de candidato doente.
- A rota só é trocada depois do health do candidato.
- Rollback e recover restauram uma versão estável.
- O ledger reflete deploys, falhas, rollback e recover.
- O `status` lista o estado e os serviços da aplicação.

## Limitações e o que não foi testado

- Host Ubuntu real, com systemd, permissões e filesystem do servidor.
- GitHub Actions de ponta a ponta em runner real.
- GHCR, DNS real e Let's Encrypt.
- Swarm multi-node, falha de nó e comportamento de HA.
- Uptime Kuma com monitores reais e notificações.
- Verificação Cosign no deploy.
- Backup e restore com dados reais.
- File watcher do Traefik em Linux.

## Conclusão

O deploy em si foi testado e está utilizável. A lógica de blue-green,
health check, rollback, recover, verify e status funciona no ambiente Linux de
containers usado no teste. Os bugs encontrados no CLI foram corrigidos e
cobertos por teste.

A ressalva é de integração: o teste não substitui uma homologação em Ubuntu
real com DNS, TLS, registry externo e pipeline. Para produção, o próximo passo
recomendado é rodar o mesmo roteiro em um staging com as mesmas versões do
servidor de destino.
