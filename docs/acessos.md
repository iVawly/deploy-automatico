# Controle de acessos

Registre a existência do acesso, o responsável e a data de revisão. **Nunca** registre senhas, chaves privadas ou tokens neste arquivo.

| Acesso | Forma | Responsável | Última revisão | Evidência (sem segredo) |
|---|---|---|---|---|
| SSH no servidor | chave ED25519, grupo `ops` | a definir |  | login de teste bem-sucedido |
| DNS do domínio | painel do registrador | a definir |  | registro A criado para `*.example.com` |
| Organização GitHub | owner | a definir |  | runner registrado |
| GHCR | token do repositório | a definir |  | push de teste privado |
| Cofre de segredos/backup | a definir | a definir |  | restauração de teste |

## Verificações

- [ ] Login por senha recusado (`ssh -o PreferredAuthentications=password`).
- [ ] Chave revogada perde acesso imediatamente.
- [ ] Grupo `ops` contém apenas os responsáveis atuais.
- [ ] Token do runner restrito ao repositório e às ações de deploy.
- [ ] Chave de autolock do Swarm guardada fora do servidor e do Git.
