# ADR 0003 — Socket proxy para o Docker

## Contexto

O Alloy precisa descobrir containers e ler logs pela API do Docker. Montar
`/var/run/docker.sock` diretamente no coletor dá a esse componente poder
equivalente a root no host, mesmo com o socket montado como read-only (o
read-only do mount não restringe a API).

## Decisão

Executar `tecnativa/docker-socket-proxy` em rede interna e apontar o Alloy para
`tcp://docker-socket-proxy:2375`. O proxy permite somente leitura (`POST=0`) e
apenas as seções necessárias (`CONTAINERS`, `EVENTS`, `INFO`, `VERSION`,
`PING`); as demais ficam bloqueadas. O socket bruto continua montado apenas no
proxy.

## Consequências

- Positivas: reduz a superfície de ataque do coletor; requisições mutantes
  recebem 403; o proxy não publica porta no host.
- Negativas: mais um componente para monitorar; se o proxy cair, o Alloy para de
  coletar logs, embora aplicação e deploy continuem.
- Risco residual: o proxy ainda tem acesso ao socket; qualquer bypass de sua
  política é crítico. Ele roda com `cap-drop ALL` e rootfs
  read-only.

## Alternativas

- Montar o socket no Alloy: simples, porém concede root efetivo ao coletor.
- Docker API via TLS: mais configuração e gestão de certificados.
- Coletar logs por arquivo no host: funciona, mas perde metadados de serviço e
  exige acesso ao filesystem do host.
