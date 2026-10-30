# Runbook: deploy

## Quando usar

Toda entrega de uma nova versão de aplicação em produção. Deploy manual no servidor não é permitido após o corte.

## Pré-requisitos

- [ ] Pull request revisado e aprovado por outra pessoa.
- [ ] Testes verdes na branch principal.
- [ ] Versão SemVer decidida (ex.: `1.4.0`), nunca `latest`.
- [ ] Janela comunicada, se a aplicação for crítica.
- [ ] Monitoramento ativo (`https://monitor.<DOMAIN>`).

## Procedimento

1. Mescle o PR na branch principal.
2. Crie e envie a tag:

   ```bash
   git checkout main
   git pull
   git tag -a v1.4.0 -m "release 1.4.0"
   git push origin v1.4.0
   ```

3. Acompanhe o workflow em GitHub → Actions → `deploy`.
   - Etapa `test`: gitleaks + testes. Falha aqui encerra o processo.
   - Etapa `build-and-deploy`: build, push no GHCR e `ops-deploy deploy demo-app 1.4.0`.

4. Confirme a versão ativa:

   ```bash
   sudo -u deployer ops-deploy status demo-app
   sudo -u deployer ops-deploy verify demo-app
   ```

   Esperado: `versão ativa: 1.4.0`, slot alternado em relação à versão anterior, `"healthy":true`.

5. Abra `https://<APP_DOMAIN>/` e confirme o comportamento esperado.
6. Registre a entrega (versão, horário, responsável) no canal da equipe.

## Em caso de falha

| Falha | Ação |
|---|---|
| Testes ou gitleaks | Corrija o código, abra novo PR; nenhuma versão foi implantada |
| Build/push | Verifique log da etapa; versão ativa não foi alterada |
| Saúde do candidato | Pipeline falha; tráfego permanece na versão anterior; investigue logs do slot candidato |
| Validação pública | A rota é restaurada automaticamente; verifique Traefik e DNS |
| Deploy concluído mas comportamento errado | Execute o [rollback](rollback.md) |

Consulte `runbooks/incidentes.md` se o serviço ativo estiver indisponível.

## Primeira instalação de uma aplicação

```bash
sudo -u deployer ops-deploy bootstrap <app> 1.0.0
```

Depois disso, todo deploy passa pelo pipeline. O bootstrap só deve ser usado uma vez por aplicação.

## Evidência para o aceite

- Log do workflow com `test` e `build-and-deploy` verdes.
- Saída de `ops-deploy status` e `ops-deploy verify`.
- Exemplo de pipeline bloqueado por teste quebrado.
