# ADR 0002 — Blue-green com file provider

## Contexto

O deploy precisa trocar tráfego sem interromper o serviço e permitir rollback
rápido, mas o ambiente não justifica um controlador de tráfego dedicado.

## Decisão

Manter dois slots (`blue` e `green`) por aplicação e alternar a rota do Traefik
por um arquivo YAML no file provider. O `ops-deploy` valida a saúde do slot
inativo antes de escrever a rota, valida o hostname público depois e restaura a
rota anterior em caso de falha.

## Consequências

- Positivas: troca atômica, rollback por arquivo, sem API externa; funciona com
  Swarm e um único nó.
- Negativas: dois serviços e dois conjuntos de containers durante a janela;
  custo de memória/CPU temporário; migração de dados não é resolvida.
- Operação: o arquivo gerado é a fonte de verdade da rota e nunca deve ser
  editado à mão.

## Alternativas

- Duas stacks completas com troca de DNS: propagação lenta e cache.
- Traefik com labels dinâmicos: exigiria recriar serviço e não dá o mesmo
  controle de validação antes da troca.
- Canary por peso: útil, mas mais complexo de validar e observar neste porte.
