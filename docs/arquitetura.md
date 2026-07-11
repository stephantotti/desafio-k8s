# Arquitetura e Justificativas Técnicas

> Documento vivo — atualizado a cada decisão técnica tomada no projeto.
> Requisito do desafio: "todas as escolhas de tecnologia devem ser justificadas
> e essas justificativas devem estar documentadas no repositório do projeto."
>
> Este arquivo cobre o **porquê** de cada escolha e os bugs encontrados
> durante o desenvolvimento. Para o **como rodar**, ver `docs/deploy.md`.
> Para acesso a dashboards/logs, ver `docs/monitoramento.md`. Para
> segurança e divergências do padrão de produção, ver `docs/seguranca.md`.

---

## 1. Ambiente Kubernetes local

**Escolha: Kind (Kubernetes IN Docker)**

- Já era a ferramenta de maior familiaridade minha — o desafio permite
  qualquer uma das opções (Kind, k3d, microk8s), desde que a solução rode em
  container e seja 100% automatizável.
- Kind não possui um cloud-controller-manager, então `Service type: LoadBalancer`
  fica `<pending>` para sempre (diferente de k3d, que já embute um `serverlb`,
  e do microk8s, que resolve isso com o addon `metallb`).
- **Mitigação adotada:** cluster criado com `extraPortMappings` mapeando as
  portas 80/443 do host para portas fixas do node (30080/30443), e o
  `Service` do `istio-ingressgateway` exposto como `NodePort` nessas mesmas
  portas. Isso reproduz o comportamento de um LoadBalancer sem depender de
  infraestrutura de nuvem — funciona igual na minha máquina e na do
  avaliador.

## 2. Service mesh / API gateway

**Escolha: Istio**

- Cobre, com uma única ferramenta, três requisitos do desafio ao mesmo tempo:
  Ingress por host (Escopo 1/3), roteamento por header de aplicação
  (Escopo 2/3) e rate limiting por serviço (Escopo 3/3) — evitando somar 3
  ferramentas diferentes (ex: NGINX Ingress + Kong + Envoy avulso) só para
  cobrir cada requisito isoladamente.
- É também a tecnologia já indicada na referência do desafio (manifests do
  Bookinfo vêm do próprio repositório do Istio).

### 2.1 Versão do Istio: por que 1.30 e não 1.13 (a referenciada no desafio)

| Istio | Kubernetes suportado |
|---|---|
| 1.13 (referência original do desafio) | 1.20 – 1.23 |
| **1.30 (adotada)** | **1.32 – 1.36** |

O Kind, na versão atual (`v0.31.0`), já cria clusters com Kubernetes 1.35 por
padrão — bem acima do que o Istio 1.13 suporta oficialmente. Rodar essa
combinação geraria falhas difíceis de diagnosticar (CRDs incompatíveis,
comportamento não testado). Optei por atualizar para o Istio **1.30**
(release com suporte ativo), que cobre exatamente a faixa de Kubernetes que
o Kind entrega hoje. Os manifests de exemplo do Bookinfo também foram
migrados da branch `release-1.13` para `release-1.30` do repositório do
Istio, para manter consistência de API entre app de exemplo e control plane.

## 3. Versões fixadas das ferramentas

| Ferramenta | Versão | Motivo da fixação |
|---|---|---|
| `kubectl` | v1.36.2 | Dentro da margem de skew (±1 minor) do node do Kind (k8s 1.35) |
| `kind` | v0.31.0 | Versão estável mais recente no momento do desenvolvimento; node default k8s 1.35 |
| `istioctl` | 1.30.2 | Release com suporte ativo, compatível com k8s 1.32–1.36 (ver seção 2.1) |
| `helm` | v3.15.3 | Estável e amplamente testado com o chart `loki-stack` usado no projeto |

Essas versões estão fixadas como constantes no `scripts/00-install-tools.sh`
— o script **não** usa "latest"/"stable" dinâmico, justamente para garantir
que o ambiente do avaliador (que pode rodar o script dias ou semanas depois)
receba exatamente as mesmas versões validadas durante o desenvolvimento.

> **Nota sobre Helm 3 vs 4:** durante o desenvolvimento, uma máquina já tinha
> o Helm v4.2.2 instalado. Optei por fixar o script na v3.15.3 porque é a
> versão com maior histórico de compatibilidade comprovada com o chart
> `grafana/loki-stack` usado na stack de logs. Quem for reproduzir o
> ambiente com Helm v4 já instalado deve validar antes se o chart
> `loki-stack` (hoje em modo de manutenção mínima) se comporta como
> esperado, já que o Helm v4 alterou parte do mecanismo de plugins e do
> `helm template`.

## 4. Instalação e verificação de ferramentas — idempotência real

A primeira versão do script apenas checava **se o binário existia**
(`command -v`), sem validar a versão. Isso é insuficiente para o requisito
de reprodutibilidade: se a máquina do avaliador já tiver, por exemplo, um
`kubectl` de uma versão muito antiga instalado por outro projeto, o script
pularia a instalação e o desafio rodaria com uma versão não testada.

**Decisão:** o script compara a versão *instalada* com a versão *fixada*
(seção 3) e força a reinstalação sempre que houver divergência,
independentemente de o binário já existir ou não.

**Decisão:** instalação em `/usr/local/bin` em vez de `~/.local/bin`. Testes
manuais mostraram que usar um diretório de usuário depende de o `$PATH` da
sessão já estar configurado corretamente (ex: `~/.bashrc` sourced, sem
outro binário mais antigo na frente no `$PATH`) — isso se mostrou frágil em
terminais integrados (ex: VS Code sobre WSL), onde o `PATH` da sessão nem
sempre reflete o `~/.bashrc` editado. `/usr/local/bin` já é prioritário no
`$PATH` padrão de qualquer distribuição Linux, eliminando essa classe de
problema.

## 5. Docker

O `kind` depende do Docker para rodar os "nodes" como containers. Como o
script roda no computador do avaliador (que pode não ter Docker instalado),
o `00-install-tools.sh`:

1. Detecta a ausência do Docker e instala automaticamente via script
   oficial (`get.docker.com`).
2. Adiciona o usuário atual ao grupo `docker` (evita precisar de `sudo` em
   todo comando docker depois).
3. Garante que o serviço/daemon está ativo (`systemctl enable --now docker`),
   já que "instalado" não significa "rodando".
4. Valida com `docker info` se o daemon está realmente respondendo antes de
   seguir — e avisa explicitamente se for necessário abrir um terminal novo
   (a permissão de grupo Unix só é aplicada em sessões novas de login).

**Trade-off aceito:** a automação usa `sudo` em pontos específicos
(instalação do Docker, cópia de binários para `/usr/local/bin`). Isso é
necessário para que o script seja de fato "encapsulado" e executável sem
comandos manuais adicionais, mas significa que o avaliador precisa rodar o
script com um usuário que tenha privilégios de sudo — premissa razoável
para uma máquina de avaliação técnica. Detalhes operacionais dessa premissa
(o que esperar na hora de rodar) estão em `docs/deploy.md`.

## 6. Namespaces

| Namespace | Propósito |
|---|---|
| `istio-system` | Control plane do Istio e ingress gateway |
| `bookinfo` | Aplicação de exemplo (productpage, reviews, ratings, details) |
| `monitoring` | Prometheus, Grafana, Kiali |
| `logging` | Loki, Promtail |

Segmentação lógica simples, que também facilita aplicar `NetworkPolicy`
restringindo tráfego entre observabilidade e aplicação, se necessário (ver
`docs/seguranca.md`).

## 7. Monitoramento — Prometheus + Grafana + Kiali

- Istio já expõe métricas do Envoy nativamente no formato Prometheus — não
  é necessário instrumentar a aplicação manualmente.
- Grafana tem dashboards oficiais prontos para Istio (Mesh, Service,
  Workload, Ingress Gateway), cobrindo o requisito de "gráfico dinamicamente
  atualizado" sem construir painéis do zero.
- Para as métricas de **packets/segundo, CPU e memória** (que o Envoy não
  expõe nativamente), uso `container_network_{receive,transmit}_packets_total`,
  `container_cpu_usage_seconds_total` e `container_memory_working_set_bytes`
  do cAdvisor — já disponíveis no Prometheus padrão do cluster, sem
  instalar nada extra.
- Kiali foi incluído como tecnologia adicional (pontuação extra mencionada
  no formato de entrega) para visualização do grafo de serviço.

Detalhes sobre a escolha addons-vs-Helm: seção 14. Como acessar e quais
dashboards existem: `docs/monitoramento.md`.

## 8. Log centralizado — Loki + Promtail

**Escolha: Loki + Promtail** (em vez de EFK/ELK completo)

- Mais leve para rodar em cluster local (Kind roda em containers Docker
  compartilhando recursos da máquina do avaliador — Elasticsearch tem
  requisitos de memória bem mais altos).
- Integra no mesmo Grafana já usado para métricas — um único painel de
  observabilidade, em vez de duas ferramentas de visualização separadas
  (Grafana + Kibana).
- Atende diretamente ao requisito de "identificar no gestor de log quando o
  request foi negado por limite de requests" (detalhes de validação e como
  consultar: `docs/monitoramento.md`).

**Alternativa avaliada e descartada por ora:** EFK (Fluent Bit +
Elasticsearch + Kibana) — mais "enterprise"/conhecido no mercado, mas exige
mais RAM/CPU para rodar bem em ambiente local, o que é um risco no dia da
avaliação (máquina do avaliador com recursos desconhecidos). Fica registrado
como possível "tecnologia extra" caso o tempo permita implementar as duas.

## 9. Rate limiting por serviço

**Escolha: `EnvoyFilter` (local rate limit) por workload**

- Não exige infraestrutura adicional (ex: Redis para rate limit global) —
  atende ao requisito com o que já está instalado (Istio/Envoy).
- Aplicado via `workloadSelector` por serviço/versão, permitindo limites
  individuais (`productpage-v1`: 5 rps, `reviews-v1/v2/v3`: 1 rps cada,
  `ratings-v1`: 1 rps, `details-v1`: 2 rps) sem afetar os demais serviços.
- Gera resposta HTTP 429 quando o limite é excedido, que fica registrada no
  access log do sidecar automaticamente (ver seção 8 e `docs/monitoramento.md`).

Escopo intencionalmente aplicado só aos 6 serviços originais do desafio —
detalhes na seção 16.

## 10. Automação

**Escolha: scripts bash + Makefile**

- Atende ao requisito "todos os comandos necessários para rodar o desafio
  devem estar encapsulados em scripts/ferramentas de automação" e à
  recomendação de "evitar comandos digitados para rodar ou testar".
- Cada etapa vira um script numerado e idempotente (`00-install-tools.sh`,
  `01-create-cluster.sh`, ...), orquestrado por um `make bootstrap`/`make up`
  único. Detalhes de uso: `docs/deploy.md`.

## 11. Escopo 1/3 — roteamento por host (limitação encontrada e solução)

**Problema encontrado:** o `productpage` oficial do Istio, ao chamar o
`reviews` internamente, só repassa um conjunto fixo e pré-definido de
headers (`x-request-id`, `cookie`, `authorization`, `end-user`, entre
outros de tracing — ver `productpage.py`, função `getForwardHeaders`). O
`Host`/`:authority` da requisição original **não está nessa lista**. Como
a chamada do `productpage` para o `reviews` é uma conexão HTTP totalmente
separada da conexão do cliente para o `productpage`, o Envoy não tem como
"lembrar" sozinho, sem ajuda da aplicação, de qual host de entrada motivou
aquela chamada interna — logo, um único `productpage-v1` compartilhado não
consegue variar a versão do `reviews` chamada com base no host externo
usando apenas configuração de rede/Istio.

**Solução adotada — sem modificar a imagem oficial:** o `productpage.py`
suporta nativamente a variável de ambiente `REVIEWS_HOSTNAME`, que
sobrescreve para qual Service ele direciona as chamadas de reviews. Usei
isso para criar 3 *variantes* do mesmo `productpage-v1` (mesma imagem
`docker.io/istio/examples-bookinfo-productpage-v1:1.16.4`), cada uma
configurada para um Service de `reviews` dedicado que seleciona diretamente
uma única versão:

| Host externo | Deployment | `REVIEWS_HOSTNAME` | Service dedicado |
|---|---|---|---|
| `simpleproduct.local` | `productpage-simpleproduct` | `reviews-v1-only` | seleciona só `version=v1` |
| `backproduct.local` | `productpage-backproduct` | `reviews-v2-only` | seleciona só `version=v2` |
| `colorproduct.local` | `productpage-colorproduct` | `reviews-v3-only` | seleciona só `version=v3` |

Os pods de `reviews-v1/v2/v3` continuam sendo os mesmos já implantados
pelo `bookinfo.yaml` — os 3 Services novos (`reviews-v1-only`, etc.) só
adicionam um seletor mais específico por cima dos mesmos pods, sem
duplicar nada. O Service `reviews` original (com os 3 subsets via
`DestinationRule`) continua existindo e é usado no Escopo 2/3.

**Alternativas consideradas e descartadas:**
- *Modificar o código do `productpage.py`* para forwarding do `Host` —
  rejeitada por exigir rebuild de uma imagem "vendor" (perde a
  rastreabilidade de usar o artefato oficial do Istio).
- *"Contrabandear" a informação de host dentro do header `cookie`* (que já
  é repassado) via reescrita no Gateway — tecnicamente viável, mas mais
  frágil/hacky que reaproveitar uma env var oficialmente suportada.
- *Match por `sourceLabels` na VirtualService do `reviews`* — não resolve,
  porque a origem da chamada (`productpage`) é sempre a mesma independente
  do host externo; `sourceLabels` não carrega informação sobre o host
  original do cliente.

## 12. Escopo 2/3 — nuance do header `end-user`

O roteamento por header `end-user` (Ted/Bill) **funciona out-of-the-box**
porque `end-user` está na lista de headers repassados pelo `productpage`
— mas com uma pegadinha: o `productpage.py` só popula esse header a partir
da **sessão logada** (`session['user']`, setada via POST em `/login`), e
não a partir de um header `end-user` enviado diretamente pelo cliente. Ou
seja: `curl -H "end-user: Ted" .../productpage` **não é suficiente** — é
necessário simular o login (POST `/login` com `username=Ted`, guardando o
cookie de sessão, e só então fazer a requisição a `/productpage` com esse
cookie). O passo a passo de teste está em `docs/deploy.md`.

## 13. Bug encontrado e corrigido — colisão de label entre productpage compartilhado e variantes

**Sintoma:** ao testar o Escopo 2/3 (roteamento por `end-user`), o login como
`Ted` retornava aleatoriamente `reviews-v2` (esperado: `v3`) — resultado
inconsistente entre tentativas.

**Causa raiz:** as 3 variantes de `productpage` criadas para o Escopo 1/3
(`productpage-simpleproduct`, `-backproduct`, `-colorproduct`) foram
criadas com o label `app: productpage` — o mesmo label usado pelo
`Service productpage` original (`bookinfo.yaml`) para selecionar seus
backends. Como o seletor do Service é `{app: productpage}` (sem mais
nenhum label), ele passou a enxergar as 3 variantes como backends válidos
também, além do `productpage-v1` real. O Kubernetes fazia round-robin
entre os 4 pods a cada requisição — e cada variante tem `REVIEWS_HOSTNAME`
fixo em uma versão específica, ignorando completamente a sessão/header
`end-user`. Cerca de 3 em cada 4 requisições caíam num pod "errado" para
esse teste.

**Correção:** label das 3 variantes trocado de `app: productpage` para
`app: productpage-variant` (Services dedicados e `matchLabels` dos
Deployments atualizados juntos). Como `spec.selector` de Deployment é
**imutável** no Kubernetes, não foi possível corrigir via `kubectl apply`
direto — foi necessário `kubectl delete deployment ... && kubectl apply
-f ...` para recriar os 3 Deployments com o novo seletor.

**Validação pós-fix:** `kubectl get endpoints productpage` confirmando
exatamente 1 endpoint (antes: 4), e 4 requisições consecutivas como `Ted`
retornando `color: red` de forma 100% consistente (antes: aleatório).

**Lição para o resto do projeto:** sempre que um novo Deployment reutilizar
um label "genérico" (`app: X`) também usado por um Service já existente,
checar explicitamente se o seletor desse Service não é amplo demais e vai
"engolir" os pods novos sem querer.

## 14. Monitoramento — addons oficiais do Istio em vez de Helm

**Escolha: `kubectl apply` dos addons oficiais** (`samples/addons/{prometheus,grafana,kiali}.yaml`
do repositório do Istio, branch `release-1.30`), não os charts Helm
padrão de mercado (`kube-prometheus-stack`, `grafana/grafana`,
`kiali/kiali-server`).

**Motivo:** os addons oficiais já vêm com toda a integração pronta —
Prometheus já configurado para fazer scrape dos sidecars Envoy e do
control plane, Grafana já com os dashboards do Istio pré-importados e o
datasource já apontando pro Prometheus certo, Kiali já com a config do
Istio Root Namespace. Via Helm puro (`kube-prometheus-stack` +
`Prometheus Operator`/`ServiceMonitor`), essa integração inteira teria que
ser recriada manualmente (dashboards importados um a um, `ServiceMonitor`
escrito à mão para capturar métricas do Envoy) — mais fiel ao "padrão de
produção", mas sem ganho funcional para o escopo deste desafio, e com
risco extra de erro de configuração sem necessidade real.

**Ajuste feito:** os 3 addons, por padrão, instalam em `istio-system`.
Foram editados (via `sed`, preservando tudo mais) para instalar em
`monitoring`, conforme a segmentação de namespaces definida na seção 6.
Isso exigiu um cuidado extra: o Kiali, quando não recebe uma URL explícita
do Prometheus, assume por padrão que ele está em `istio-system` — como os
dois passaram a viver em `monitoring`, foi necessário adicionar
`external_services.prometheus.url: "http://prometheus.monitoring:9090"`
manualmente na config do Kiali (esse valor não vem preenchido no addon
oficial, que assume ambos no mesmo namespace `istio-system` por padrão).
A `root_namespace: istio-system` do Kiali foi **mantida** — refere-se a
onde o control plane do Istio (istiod) roda, não a onde o Kiali roda, e
portanto está correta sem alteração. Mesmo ajuste de namespace foi feito
para o datasource Loki (`http://loki.logging:3100`), que também assume por
padrão o mesmo namespace do Grafana.

## 15. Testes/tráfego gerado

`scripts/07-generate-traffic.sh` bate nos 3 hosts do Escopo 1/3 e simula os
3 casos do Escopo 2/3 (Ted/Bill/sem login) em loop, por um tempo
configurável, só para popular os dashboards com dado real antes de uma
demonstração — não faz parte da aplicação em si.

## 16. Escopo 3/3 — rate limiting: escopo aplicado só aos 6 serviços originais

O `workloadSelector` dos `EnvoyFilter` usa `app: productpage, version: v1`
— que bate com o `productpage-v1` original, mas não com as 3 variantes
criadas para o Escopo 1/3 (`productpage-simpleproduct/backproduct/colorproduct`,
que têm `app: productpage-variant`). Isso é intencional: a tabela de
limites do desafio lista exatamente os 6 workloads originais do
`bookinfo.yaml`. As 3 variantes ficam sem rate limit dedicado nesta
entrega — possível melhoria futura, mas fora do escopo literal pedido.

## 17. Bug real: validação de sidecar não reconhecia "native sidecar containers"

**Sintoma:** `make up`/`make bootstrap` falhava na validação do
`03-deploy-bookinfo.sh` ("Pod(s) acima SEM sidecar istio-proxy injetado
após 6 tentativas"), mesmo com os pods saudáveis e o Envoy funcionando
normalmente (confirmado via `kubectl describe pod` mostrando o container
`istio-proxy` criado e iniciado com sucesso).

**Causa raiz:** no Kubernetes 1.28+ (meu cluster roda 1.35) existe a
feature de **"native sidecar containers"**: um container pode ser
declarado como `initContainer` com `restartPolicy: Always`, fazendo ele
se comportar como um sidecar de verdade (inicia antes do container
principal, mas continua rodando durante toda a vida do pod) — em vez do
padrão antigo, onde sidecars eram `containers` comuns citados junto com o
container da aplicação. O Istio 1.30, ao detectar que o cluster suporta
essa feature, injeta o `istio-proxy` como **native sidecar** por padrão —
ou seja, ele aparece em `spec.initContainers`, não em `spec.containers`.

A validação original só checava `.spec.containers[*].name`, nunca
encontrando o `istio-proxy` ali (porque genuinamente não está mais
naquele campo nas versões modernas), gerando falso negativo consistente
— não era mais um problema de timing/propagação como da primeira vez, e
sim uma checagem desatualizada para a versão do Kubernetes/Istio usada
neste projeto.

**Correção:** a validação em `03-deploy-bookinfo.sh` verifica tanto
`.spec.containers[*].name` quanto `.spec.initContainers[*].name`, cobrindo
os dois formatos (sidecar clássico e sidecar nativo).

**Evidência de diagnóstico:**
```
$ kubectl get pod -l app=details -o jsonpath='{.spec.initContainers[*].name}'
istio-init istio-proxy
$ kubectl get pod -l app=details -o jsonpath='{.spec.containers[*].name}'
details
```

## 18. Bug real: checagem de porta antes de checar se o cluster já existe

**Sintoma:** depois de reiniciar a máquina e rodar `make up` de novo, o
`01-create-cluster.sh` falhava com "Porta 80 já está em uso no host" —
mesmo o cluster já existindo e sendo exatamente o dono legítimo dessa
porta (via `extraPortMappings`).

**Causa raiz:** o script checava se as portas 80/443 estavam livres **antes**
de checar se o cluster já existia. Depois de um reboot, o container do
node (que já tinha sido recriado/religado, seja automaticamente pelo
Docker ou manualmente) já ocupava a porta 80 de propósito — mas o script
tratava isso como um conflito externo, sem primeiro considerar que talvez
não houvesse nada para criar.

**Correção:** reordenado para checar primeiro se o cluster já existe
(`kind get clusters`). Se existir, pula tanto a criação quanto a checagem
de porta — e ainda garante que o container Docker do node está `running`
(reiniciando com `docker start` se necessário), evitando que um
`kubectl wait` trave esperando um node que nunca vai responder. A
checagem de porta só roda no caminho de "vou criar um cluster novo de
verdade", onde ela genuinamente faz sentido.

---

### Histórico de decisões (ordem cronológica, para acompanhar a evolução)

1. Definição do stack geral (Kind + Istio + Prometheus/Grafana + Loki).
2. Ajuste de Kind para expor Ingress sem LoadBalancer nativo.
3. Detecção de incompatibilidade Istio 1.13 × Kubernetes 1.35 (Kind atual) →
   upgrade para Istio 1.30 e troca da branch de manifests de referência.
4. Fixação de versões exatas das ferramentas para reprodutibilidade entre a
   minha máquina e a do avaliador.
5. Correção do script de instalação para checar versão (não só presença) e
   evitar reutilização de binários antigos já presentes na máquina.
6. Automação da instalação/verificação do Docker, incluindo checagem do
   daemon ativo — não só do binário instalado.
7. Descoberta de que o `productpage` não repassa o `Host` original ao
   chamar o `reviews` → solução via 3 variantes de `productpage` usando a
   env var oficial `REVIEWS_HOSTNAME`, sem modificar a imagem.
8. Identificação de pegadinha equivalente no Escopo 2/3 (`end-user` só é
   repassado via sessão logada, não via header cru).
9. Bug de colisão de label entre productpage compartilhado e variantes
   (seção 13) — corrigido e validado.
10. Migração dos addons de observabilidade para o namespace `monitoring`,
    com ajustes de URL cross-namespace (Kiali, Loki).
11. Adição de painéis de CPU/memória (requisito geral que estava faltando)
    e dos scripts de acesso/retomada (`access-dashboards.sh`,
    `resume-cluster.sh`), Makefile consolidado, e alias/env var do kubectl.
12. Bug de validação de sidecar não reconhecendo native sidecar containers
    (seção 17) — corrigido.
13. Bug de ordem de checagem no `01-create-cluster.sh` (porta antes de
    existência do cluster) — corrigido, com robustez extra para container
    parado após reboot (seção 18).