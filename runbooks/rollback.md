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

1. Exige sonda pública que confirme versão; sem isso, recusa salvo `OPS_DEPLOY_ALLOW_UNVERIFIED=1` (registrado com aviso).
2. Exige consistência entre rota desejada e ledger e confirma que o tráfego público já serve a versão atual. Divergência ou aplicação pendente do Traefik bloqueia o rollback; diagnostique com `ops-deploy doctor <app>`.
3. Identifica a versão alvo e o digest no ledger `/var/lib/ops-deploy/releases.jsonl`; registro legado sem digest exige `OPS_DEPLOY_ALLOW_MUTABLE_TAG=1`.
4. Baixa a imagem já publicada (não reconstrói).
5. Sobe a versão alvo no slot inativo e aguarda saúde profunda (e a versão, quando `APP_HEALTH_EXPECT_VERSION=1`).
6. Troca a rota do Traefik e valida o hostname público, exigindo a versão alvo quando `APP_PUBLIC_EXPECT_VERSION=1`.
7. Reduz o slot anterior a zero após a janela de drenagem, salvo `APP_KEEP_PREVIOUS=1`.
8. Registra `action=rollback` com autor, origem e destino.

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
- **Depois da troca:** a versão restaurada é mantida para diagnóstico; um alerta crítico é enviado se `OPS_DEPLOY_ALERT_WEBHOOK` estiver configurado e o CLI registra `WARN` caso contrário. Não execute novo rollback às cegas; siga `runbooks/incidentes.md`.

Nesse estado, a rota aponta para o alvo mas o ledger ainda tem a última release bem-sucedida anterior. **Não rode outro `deploy` ou `rollback` antes de reconciliar** (o comando bloqueia e evita remover o slot em serviço). Diagnostique e escolha explicitamente:

```bash
sudo -u deployer ops-deploy doctor <app>
# a rota é a verdade (ex.: alvo restaurado será mantido):
sudo -u deployer ops-deploy reconcile <app> --accept-route
# o ledger é a verdade (ex.: voltar ao que estava registrado):
sudo -u deployer ops-deploy reconcile <app> --accept-ledger
```

Depois da reconciliação, rode `doctor` novamente e só então siga com o próximo deploy/rollback.

## Evidência para o aceite

- Saída de `status` antes e depois.
- Tempo total medido.
- Registro no ledger com `action":"rollback"`.
- Confirmação de que o volume manteve os dados.
