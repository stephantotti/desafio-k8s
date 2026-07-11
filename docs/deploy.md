# Deploy — Como Rodar o Projeto

> Este documento cobre **como colocar o ambiente de pé e testar cada
> escopo**. Para o porquê de cada decisão técnica, ver `docs/arquitetura.md`.
> Para acessar dashboards e logs, ver `docs/monitoramento.md`.

## Pré-requisitos

- Linux (testado em Ubuntu via WSL2)
- Usuário com `sudo` **sem exigência de senha interativa recorrente**
  (ver `docs/arquitetura.md`, seção 5) — se pedir senha uma vez no meio da
  execução, é esperado, só digite e deixe continuar.
- Conexão com a internet (baixa binários, imagens Docker, charts Helm)

Tudo o mais (Docker, kubectl, kind, istioctl, helm) é instalado
automaticamente pelo primeiro script — não precisa instalar nada à mão
antes de começar.

## Rodando o ambiente completo

Na raiz do repositório:

```bash
make up
```

(alias de `make bootstrap` — os dois fazem exatamente a mesma coisa)

Isso executa, em sequência, todos os scripts numerados em `scripts/`:

| Ordem | Script | O que faz |
|---|---|---|
| 1 | `00-install-tools.sh` | Instala kubectl/kind/istioctl/helm em versões fixas |
| 2 | `01-create-cluster.sh` | Cria o cluster Kind (ou religa se já existir) |
| 3 | `02-install-istio.sh` | Instala o Istio + cria os namespaces do projeto |
| 4 | `03-deploy-bookinfo.sh` | Aplica a aplicação Bookinfo + valida injeção de sidecar |
| 5 | `04-apply-routing.sh` | Aplica o roteamento por host (Escopo 1/3) |
| 6 | `05-apply-enduser-routing.sh` | Aplica o roteamento por `end-user` (Escopo 2/3) |
| 7 | `06-install-observability.sh` | Instala Prometheus/Grafana/Kiali + dashboard customizado |
| 8 | `08-apply-ratelimit.sh` | Aplica o rate limiting por serviço (Escopo 3/3) |
| 9 | `09-install-logging.sh` | Instala Loki/Promtail |
| 10 | `configure-kubectl-env.sh` | Configura alias `k` e `KUBECONFIG` dedicado |

Leva alguns minutos na primeira vez (baixando imagens Docker). Rodar de
novo depois é rápido — todos os scripts são idempotentes, então `make up`
pode ser chamado quantas vezes precisar sem duplicar nada ou quebrar o
que já está no ar.

Ao final, o terminal mostra `>>> Ambiente completo`.

## Rodando etapas isoladamente

Cada linha da tabela acima também é um alvo do Makefile, caso precise
reexecutar só uma parte:

```bash
make install-tools
make cluster
make istio
make bookinfo
make routing
make enduser
make observability
make ratelimit
make logging
make kubectl-env
```

## Derrubando o ambiente

```bash
make down
```
(alias de `make destroy`) — remove o cluster Kind por completo.

## Retomando depois de reiniciar a máquina

Containers do Kind sobrevivem a um `docker start`, mas sessões de terminal
com `port-forward` aberto não sobrevivem a um reboot. Ao voltar a trabalhar
no projeto (nova sessão, ou depois de desligar o PC):

```bash
scripts/resume-cluster.sh
```

Esse script garante que o container do cluster está rodando, espera o node
ficar `Ready`, confirma a saúde de todos os pods, e reabre os túneis de
acesso automaticamente. Também é seguro rodar mesmo se nada tiver caído —
é idempotente, então pode virar seu comando padrão de início de sessão.

`make up`/`make bootstrap` também já lida bem com esse cenário: o
`01-create-cluster.sh` detecta se o cluster já existe e, nesse caso,
garante que o container está `running` antes de seguir (sem tentar criar
um cluster novo nem falhar por causa de portas "ocupadas" pelo próprio
cluster já existente).

## kubectl: alias e variável de ambiente

Depois de rodar `make up` (ou `scripts/configure-kubectl-env.sh`
isoladamente), abra um terminal novo ou rode `source ~/.bashrc` para
ativar:

```bash
k get nodes
```

`k` é um alias para `kubectl --context kind-bookinfo-challenge`, e a
variável `KUBECONFIG` aponta para um kubeconfig dedicado deste projeto
(`~/.kube/bookinfo-challenge.config`), isolado do `~/.kube/config` geral
da máquina.

## Como testar cada escopo

### Escopo 1/3 — roteamento por host

```bash
curl -s --resolve simpleproduct.local:80:127.0.0.1 http://simpleproduct.local/productpage | grep -o "glyphicon-star[a-z -]*"
curl -s --resolve backproduct.local:80:127.0.0.1  http://backproduct.local/productpage  | grep -o "glyphicon-star[a-z -]*"
curl -s --resolve colorproduct.local:80:127.0.0.1 http://colorproduct.local/productpage | grep -o "glyphicon-star[a-z -]*"
```

Esperado: `simpleproduct` sem estrelas (reviews-v1), `backproduct` com
estrelas (reviews-v2), `colorproduct` com estrelas (reviews-v3). A
diferença visual entre v2/v3 é sutil no HTML puro (cor via `style`
inline) — para confirmar sem ambiguidade, teste os Services isolados
diretamente:

```bash
kubectl run tmp-curl --rm -it --image=curlimages/curl --restart=Never -n bookinfo -- sh -c '
curl -s http://reviews-v1-only:9080/reviews/0; echo
curl -s http://reviews-v2-only:9080/reviews/0; echo
curl -s http://reviews-v3-only:9080/reviews/0; echo
'
```

### Escopo 2/3 — roteamento por `end-user`

**Importante:** ver `docs/arquitetura.md` seção 12 — `end-user` só é
repassado a partir de uma sessão logada, não de um header cru enviado
direto pelo cliente. O teste precisa simular o login de verdade:

```bash
# Ted -> deve cair em reviews-v3 (color: red)
curl -s -c /tmp/cookie_ted.txt --resolve bookinfo.local:80:127.0.0.1 -d "username=Ted" http://bookinfo.local/login -o /dev/null
curl -s -b /tmp/cookie_ted.txt --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/api/v1/products/0/reviews

# Bill -> deve cair em reviews-v2 (color: black)
curl -s -c /tmp/cookie_bill.txt --resolve bookinfo.local:80:127.0.0.1 -d "username=Bill" http://bookinfo.local/login -o /dev/null
curl -s -b /tmp/cookie_bill.txt --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/api/v1/products/0/reviews

# sem login -> deve cair em reviews-v1 (sem campo "rating")
curl -s --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/api/v1/products/0/reviews
```

### Escopo 3/3 — rate limiting

```bash
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/productpage
done
echo
```

Esperado: mistura de `200` e `429` (limite do `productpage-v1`: 5 req/s).
Para conferir a identificação no log, ver `docs/monitoramento.md`.

### Gerar tráfego contínuo (para popular dashboards)

```bash
scripts/07-generate-traffic.sh 60
```

Bate nos 3 hosts do Escopo 1/3 e simula os 3 casos do Escopo 2/3 em loop
por 60 segundos (ajustável, ex: `... 120` para 2 minutos).