# Monitoramento e Log — Como Acessar

> Este documento cobre **como acessar e usar** a stack de observabilidade.
> Para o porquê de cada escolha de ferramenta, ver `docs/arquitetura.md`.

## Stack instalada

| Ferramenta | Namespace | Função |
|---|---|---|
| Prometheus | `monitoring` | Coleta de métricas (Envoy, cAdvisor) |
| Grafana | `monitoring` | Dashboards de métricas |
| Kiali | `monitoring` | Grafo de serviço do mesh |
| Loki + Promtail | `logging` | Agregação de logs de todos os pods |

## Acesso

Os `Services` de Grafana/Kiali/Prometheus são `ClusterIP` — só resolvem
dentro do cluster. Acesso é via `port-forward`, gerenciado pelo script
dedicado (não rode os comandos manualmente — ver o porquê em
`docs/arquitetura.md`, mas resumindo: evita processos órfãos e confirma
com `curl` que cada túnel está respondendo de verdade):

```bash
scripts/access-dashboards.sh
```

Já é chamado automaticamente no final do `06-install-observability.sh` /
`make observability`. Rode manualmente sempre que: reiniciar algum
Deployment em `monitoring`, os dashboards pararem de responder, ou depois
de `scripts/resume-cluster.sh`.

URLs:
- **Grafana:** http://localhost:3000 (sem login — acesso anônimo como Admin)
- **Kiali:** http://localhost:20001
- **Prometheus:** http://localhost:9090

Para encerrar os túneis: `pkill -9 -f "kubectl port-forward.*-n monitoring"`

**Nota:** parar o `port-forward` (Ctrl+C ou fechar o terminal) encerra só
o túnel local — não afeta o Grafana/Prometheus/Kiali nem a aplicação
Bookinfo, que continuam rodando normalmente no cluster. Para reconectar,
rode `scripts/access-dashboards.sh` de novo.

## Dashboards disponíveis no Grafana

Na pasta **istio** (menu Dashboards):

- **Istio Mesh Dashboard** — visão geral de tráfego, taxa de sucesso, e
  uma tabela com requests/latência/sucesso por cada workload individual
  (cobre "monitorar todos os serviços individualmente").
- **Istio Service Dashboard**, **Istio Workload Dashboard**, **Istio
  Control Plane Dashboard** — dashboards oficiais do Istio, mais
  detalhados por recurso.
- **Bookinfo - Ingress, Servicos e Recursos (Custom)** — dashboard
  próprio deste projeto, com 3 linhas:
  1. **Ingress Gateway** (Escopo 1/3): Requests/s, Bytes/s, Packets/s
  2. **Por Serviço** (Escopo 2/3): mesma tríade, com um dropdown
     `$workload` no topo para escolher qual serviço ver
  3. **Recursos — Todos os Serviços**: CPU e memória de todos os pods do
     `bookinfo` ao mesmo tempo (requisito geral do desafio)

## Kiali

Acesse http://localhost:20001 → **Overview** já mostra RPS de
entrada/saída e a saúde de todos os workloads. **Traffic Graph** (menu
lateral) dá uma visualização em grafo do tráfego real entre os serviços —
bom para a apresentação, mostra visualmente o roteamento por host e por
`end-user` acontecendo.

## Verificar rate limit no log (Escopo 3/3)

1. Gere tráfego que estoure o limite: `scripts/08-apply-ratelimit.sh` (ou
   qualquer teste de carga contra `productpage-v1`, limite 5 req/s).
2. Abra http://localhost:3000 (Grafana).
3. Menu lateral → **Explore**.
4. Seletor de datasource no topo → troque de "Prometheus" para **Loki**.
5. No editor de query, clique em **Code** (ao lado de "Builder") — evita
   que a interface tente separar a query em campos automaticamente.
6. Cole:
   ```
   {namespace="bookinfo"} |= "local_rate_limited"
   ```
7. **Run query**.

O painel **Logs** deve listar as linhas onde o Envoy bloqueou por rate
limit. Exemplo de linha real:
```
"GET /productpage HTTP/1.1" 429 RL local_rate_limited - "-" 0 18 0 - "10.244.0.1" "curl/8.5.0" "<request-id>" "bookinfo.local" ...
```

`local_rate_limited` é o response flag que o Envoy grava especificamente
quando é o rate limit local que bloqueou a requisição — mais preciso que
buscar só o código `429` (que teoricamente poderia aparecer por outros
motivos). O log padrão do Envoy é texto posicional, não JSON, por isso a
busca é por substring, não por campo nomeado.

**Se aparecer "No data":** não há requisições bloqueadas na janela de
tempo selecionada (canto superior direito, ex: "Last 1 hour"). Gere mais
tráfego e repita a query.

**Se aparecer o aviso "Failed to load log volume for this query":** é só
o painel auxiliar de volume (gráfico de barras) que não processou a
query — não afeta o painel principal de Logs, abaixo dele. Pode ignorar.

## Prometheus direto (queries manuais)

Útil para depurar métricas antes de colocar num painel:

```
sum(rate(istio_requests_total{reporter="destination", destination_workload_namespace="bookinfo"}[5m])) by (destination_workload)
sum(rate(container_network_receive_packets_total{namespace="bookinfo"}[5m])) by (pod)
sum(rate(container_cpu_usage_seconds_total{namespace="bookinfo"}[5m])) by (pod)
sum(container_memory_working_set_bytes{namespace="bookinfo"}) by (pod)
```

Acesse via http://localhost:9090 → aba **Query**.