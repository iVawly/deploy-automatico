# Runbook: rollback

## Quando usar

- A versão nova apresenta erro funcional, degradação ou indisponibilidade após o deploy.
- O monitoramento acusa falha correlacionada à última versão.
- Há decisão do responsável pela aplicação.

Rollback não é usado para mascarar falha de dependência externa sem relação com a versão; nesse caso siga `runbooks/incidentes.md`.

## Comando

Última versão estável anterior:

```bash
sudo -u deployer ops-deploy rollback <app>
```

Versão específica (precisa constar no histórico como estável):

```bash
sudo -u deployer ops-deploy rollback <app> 1.3.2
```

## O que o comando faz

1. Identifica a versão alvo no ledger `/var/lib/ops-deploy/releases.jsonl`.
2. Baixa a imagem já publicada (não reconstrói).
3. Sobe a versão alvo no slot inativo e aguarda saúde profunda.
4. Troca a rota do Traefik e valida o hostname público.
5. Reduz o slot anterior a zero após a janela de drenagem.
6. Registra `action=rollback` com autor, origem e destino.

O volume persistente é preservado; nenhum `docker volume rm` é executado.

## Verificação

```bash
sudo -u deployer ops-deploy status <app>
sudo -u deployer ops-deploy verify <app>
curl -sS -o /dev/null -w '%{http_code}\n' https://<APP_DOMAIN>/
```

Esperado: versão alvo ativa, `"healthy":true`, HTTP 200 na URL pública.

## Critério de sucesso

- Rollback concluído em até 5 minutos a partir do acionamento.
- Versão anterior atendendo todo o tráfego.
- Registro de rollback no ledger.
- Dados persistentes acessíveis.

## Se o rollback falhar

- **Antes da troca de tráfego:** a versão atual continua ativa; o comando retorna erro. Investigue a saúde da versão alvo.
- **Depois da troca:** a versão restaurada é mantida para diagnóstico e um alerta crítico é emitido. Não execute novo rollback às cegas; siga `runbooks/incidentes.md`.

## Evidência para o aceite

- Saída de `status` antes e depois.
- Tempo total medido.
- Registro no ledger com `action":"rollback"`.
- Confirmação de que o volume manteve os dados.
