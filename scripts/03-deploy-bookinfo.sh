#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 03-deploy-bookinfo.sh
#
# Aplica o bookinfo.yaml + destination-rule-all.yaml no namespace 'bookinfo'
# e valida que a injeção de sidecar do Istio funcionou (pods 2/2, não 1/1).
# ---------------------------------------------------------------------------

NAMESPACE="bookinfo"
EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests/bookinfo"

log()  { printf '\n\033[1;34m[deploy-bookinfo]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."

[ -f "${MANIFESTS_DIR}/bookinfo.yaml" ]            || fail "Não encontrei ${MANIFESTS_DIR}/bookinfo.yaml"
[ -f "${MANIFESTS_DIR}/destination-rule-all.yaml" ] || fail "Não encontrei ${MANIFESTS_DIR}/destination-rule-all.yaml"

# ---------------------------------------------------------------------------
# Confirmar que a injeção de sidecar está habilitada ANTES de aplicar —
# se aplicarmos sem isso, os pods sobem sem Envoy e nada de roteamento/
# rate-limit funciona depois (erro difícil de diagnosticar depois de subir).
# ---------------------------------------------------------------------------
INJECTION_LABEL="$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || true)"
if [ "$INJECTION_LABEL" != "enabled" ]; then
  fail "Namespace '${NAMESPACE}' sem istio-injection=enabled. Rode antes: scripts/02-install-istio.sh"
fi

log "Aplicando bookinfo.yaml..."
kubectl apply -n "$NAMESPACE" -f "${MANIFESTS_DIR}/bookinfo.yaml"

log "Aplicando destination-rule-all.yaml..."
kubectl apply -n "$NAMESPACE" -f "${MANIFESTS_DIR}/destination-rule-all.yaml"

log "Aguardando os deployments ficarem prontos..."
for DEPLOY in details-v1 ratings-v1 reviews-v1 reviews-v2 reviews-v3 productpage-v1; do
  kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOY}" --timeout=180s
done

# ---------------------------------------------------------------------------
# Validar que a injeção de sidecar REALMENTE aconteceu (2/2, não 1/1)
# Com retry: logo após o rollout status, a query pode momentaneamente não
# refletir o container istio-proxy ainda (propagação do estado no cluster),
# gerando falso negativo. Tenta por até 30s antes de considerar falha real.
# ---------------------------------------------------------------------------
log "Validando injeção de sidecar (esperado: 2/2 em cada pod)..."
ATTEMPTS=0
MAX_ATTEMPTS=6
while [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
  NOT_INJECTED="$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{" "}{.spec.initContainers[*].name}{"\n"}{end}' | grep -v 'istio-proxy' || true)"
  if [ -z "$NOT_INJECTED" ]; then
    break
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 5
done

if [ -n "$NOT_INJECTED" ]; then
  echo "$NOT_INJECTED"
  fail "Pod(s) acima SEM sidecar istio-proxy injetado após ${MAX_ATTEMPTS} tentativas. Verifique o label istio-injection e recrie os pods (kubectl delete pod <nome> -n ${NAMESPACE})."
fi

log "Concluído. Resumo:"
kubectl get pods -n "$NAMESPACE"
kubectl get destinationrules -n "$NAMESPACE"

echo
echo "Teste rápido (ainda sem Gateway/VirtualService — deve dar 404, não timeout):"
echo "    curl -sI http://localhost/"
echo
echo "Próximo passo: aplicar o Gateway + VirtualServices (Escopo 1/3 e 2/3)."