#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 02-install-istio.sh
#
# Instala o Istio (profile demo) no cluster criado pelo 01-create-cluster.sh,
# cria os namespaces do projeto e habilita a injeção automática de sidecar
# no namespace 'bookinfo'. Também expõe o istio-ingressgateway como NodePort
# nas portas 30080/30443, batendo com o extraPortMappings do kind-config.yaml.
# ---------------------------------------------------------------------------

CLUSTER_NAME="bookinfo-challenge"
EXPECTED_CONTEXT="kind-${CLUSTER_NAME}"

log()  { printf '\n\033[1;34m[install-istio]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v istioctl >/dev/null 2>&1 || fail "istioctl não encontrado. Rode antes: scripts/00-install-tools.sh"
command -v kubectl  >/dev/null 2>&1 || fail "kubectl não encontrado. Rode antes: scripts/00-install-tools.sh"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]; then
  fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'. Rode antes: scripts/01-create-cluster.sh"
fi

# ---------------------------------------------------------------------------
# Instalação do Istio (idempotente — istioctl install já reconcilia sozinho)
# ---------------------------------------------------------------------------
log "Instalando Istio (profile demo)..."
istioctl install --set profile=demo -y

log "Aguardando istiod e os gateways ficarem prontos..."
kubectl -n istio-system rollout status deployment/istiod --timeout=180s
kubectl -n istio-system rollout status deployment/istio-ingressgateway --timeout=180s
kubectl -n istio-system rollout status deployment/istio-egressgateway --timeout=180s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Namespaces do projeto (segmentação lógica — ver docs/arquitetura.md seção 6)
# ---------------------------------------------------------------------------
for NS in bookinfo monitoring logging; do
  if kubectl get namespace "$NS" >/dev/null 2>&1; then
    log "Namespace '${NS}' já existe — pulando."
  else
    log "Criando namespace '${NS}'..."
    kubectl create namespace "$NS"
  fi
done

log "Habilitando injeção automática de sidecar no namespace 'bookinfo'..."
kubectl label namespace bookinfo istio-injection=enabled --overwrite

# ---------------------------------------------------------------------------
# Expor o ingress gateway como NodePort fixo (substitui o LoadBalancer)
# ---------------------------------------------------------------------------
log "Configurando istio-ingressgateway como NodePort (30080/30443)..."

# Substitui o array de portas INTEIRO, de uma vez só (patch atômico). Fazer
# patches incrementais porta-a-porta (ex: /spec/ports/0) é frágil: o profile
# demo tem portas extras (status-port, tls) que podem já ter sido
# auto-atribuídas pelo Kubernetes para 30080/30443 por acaso, causando erro
# de "duplicate nodePort" ao tentar fixar outra porta no mesmo valor. Aqui:
# fixamos http2→30080 e https→30443 e LIBERAMOS o nodePort das demais portas
# (removendo o campo, deixando o Kubernetes reatribuir automaticamente) —
# isso também autocorrige qualquer conflito já existente no cluster.
NEW_PORTS_JSON="$(kubectl get svc istio-ingressgateway -n istio-system -o json | python3 -c '
import json, sys
svc = json.load(sys.stdin)
ports = svc["spec"]["ports"]
for p in ports:
    if p.get("name") == "http2":
        p["nodePort"] = 30080
    elif p.get("name") == "https":
        p["nodePort"] = 30443
    else:
        p.pop("nodePort", None)
print(json.dumps(ports))
')"

kubectl patch svc istio-ingressgateway -n istio-system --type merge \
  -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":${NEW_PORTS_JSON}}}"

log "Concluído. Resumo:"
kubectl get pods -n istio-system
kubectl get namespaces
kubectl get svc istio-ingressgateway -n istio-system

echo
echo "Teste rápido (deve responder algo, mesmo sem o bookinfo aplicado ainda):"
echo "    curl -sI http://localhost/"