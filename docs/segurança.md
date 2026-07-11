# Segurança

> "Aspectos de segurança serão avaliados na apresentação" — este documento
> reúne os pontos a discutir: o que foi implementado, o que ficou como
> divergência consciente do padrão de produção, e o que ainda está pendente.

## Divergências conscientes do padrão de produção

Lista de pontos onde este projeto **conscientemente** se afasta do que
seria considerado "padrão de mercado para produção" — decisão tomada por
ser um ambiente de desafio técnico/avaliação local, não produção real.

| Ponto | O que foi feito | O que seria "produção" | Por quê |
|---|---|---|---|
| Observabilidade | Addons oficiais via `kubectl apply` | Helm + Prometheus Operator + `ServiceMonitor` | Integração já pronta nos addons, sem ganho real aqui (ver `docs/arquitetura.md` seção 14) |
| Persistência do Prometheus | `emptyDir` (perde histórico ao reiniciar o pod) | `PersistentVolumeClaim` | Ambiente efêmero de avaliação, não precisa reter métricas entre sessões |
| Ingress/TLS | Só HTTP (porta 80), sem certificado | HTTPS com cert (cert-manager, Let's Encrypt ou CA interna) | Sem domínio real/DNS público para emitir certificado; fora do escopo do desafio |
| mTLS entre serviços | **Pendente** — ver seção abaixo | `STRICT` mTLS no namespace | Candidato a implementar antes da apresentação |
| Réplicas dos serviços | 1 réplica por Deployment | Múltiplas réplicas + `PodDisruptionBudget` | Ambiente local (Kind) com recursos limitados da máquina do avaliador |
| Autenticação Grafana/Kiali | Acesso sem login (`GF_AUTH_ANONYMOUS_ENABLED=true` como Admin) | SSO/OAuth na frente dos dashboards | Acesso só via `port-forward` local, nunca exposto publicamente |
| Profile do Istio | `demo` (recursos reduzidos, tracing ligado) | `default` (voltado a produção) | Profile recomendado pelo próprio Istio para este cenário |
| `sudo` no script de instalação | Assume `sudo` sem senha | Menor privilégio, sem `sudo` em automação | Necessário para cumprir "zero comando manual" (ver `docs/arquitetura.md` seção 5) |

## mTLS — pendência a resolver

O Istio, por padrão, roda em modo `PERMISSIVE` (aceita tráfego com e sem
mTLS). Para forçar `STRICT` no namespace `bookinfo`:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: bookinfo
spec:
  mtls:
    mode: STRICT
```

**Antes de aplicar em definitivo**, testar que não quebra nenhum fluxo já
validado (Escopo 1/3, 2/3, 3/3) — em teoria não deveria, já que mTLS é
transparente para a aplicação (os sidecars cuidam da criptografia entre
si), mas vale confirmar na prática antes da apresentação.

## Rate limiting como controle de segurança

O rate limiting do Escopo 3/3 (`EnvoyFilter` local, ver
`docs/arquitetura.md` seção 9) não é só um requisito funcional — também
funciona como uma primeira camada de proteção básica contra abuso/DoS
simples em nível de aplicação, limitando quantas requisições por segundo
cada serviço aceita processar.

## Outras considerações

- **Isolamento de namespaces:** a segmentação lógica (`bookinfo`,
  `istio-system`, `monitoring`, `logging` — ver `docs/arquitetura.md`
  seção 6) facilita aplicar `NetworkPolicy` restringindo tráfego entre
  observabilidade e aplicação, caso necessário — não implementado nesta
  entrega, mas a estrutura já suporta.
- **Imagens não modificadas:** todas as imagens usadas são as oficiais do
  Istio/Bookinfo (`docker.io/istio/examples-bookinfo-*`), sem builds
  customizados — reduz superfície de risco de imagem comprometida e
  mantém rastreabilidade até a origem oficial.
- **`securityContext`:** os containers da aplicação já rodam com
  `runAsUser: 1000` (não-root), herdado do `bookinfo.yaml` oficial.
- **kubeconfig isolado:** o script de configuração do `kubectl`
  (`configure-kubectl-env.sh`) usa um kubeconfig dedicado a este projeto
  (`~/.kube/bookinfo-challenge.config`), evitando misturar credenciais/
  contextos com outros clusters que o avaliador possa ter na máquina.