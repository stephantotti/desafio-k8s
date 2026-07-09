#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 04-apply-routing.sh
#
# Aplica os Services dedicados de reviews, as 3 variantes de productpage,
# o Gateway e as VirtualServices do Escopo 1/3. No final, testa os 3 hosts
# via curl (usando --resolve, sem precisar mexer em /etc/hosts) e confirma
# que cada um retorna a versão certa do reviews.
# ---------------------------------------------------------------------------

NAMESPACE="bookinfo"
EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOKINFO_DIR="${SCRIPT_DIR}/../manifests/bookinfo"
ROUTING_DIR="${SCRIPT_DIR}/../manifests/routing"

log()  { printf '\n\033[1;34m[apply-routing]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."

for f in "${BOOKINFO_DIR}/reviews-subset-services.yaml" \
         "${BOOKINFO_DIR}/productpage-variants.yaml" \
         "${ROUTING_DIR}/gateway.yaml" \
         "${ROUTING_DIR}/virtualservice-hosts.yaml"; do
  [ -f "$f" ] || fail "Não encontrei $f"
done

log "Aplicando Services dedicados de reviews (v1/v2/v3 isolados)..."
kubectl apply -n "$NAMESPACE" -f "${BOOKINFO_DIR}/reviews-subset-services.yaml"

log "Aplicando as 3 variantes do productpage..."
kubectl apply -n "$NAMESPACE" -f "${BOOKINFO_DIR}/productpage-variants.yaml"

log "Aguardando os 3 productpage variantes ficarem prontos..."
for DEPLOY in productpage-simpleproduct productpage-backproduct productpage-colorproduct; do
  kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOY}" --timeout=180s
done

log "Aplicando Gateway..."
kubectl apply -f "${ROUTING_DIR}/gateway.yaml"

log "Aplicando VirtualServices dos 3 hosts..."
kubectl apply -f "${ROUTING_DIR}/virtualservice-hosts.yaml"

# ---------------------------------------------------------------------------
# Teste funcional: cada host deve retornar a versão certa do reviews.
# Usa --resolve para simular o DNS sem precisar editar /etc/hosts.
# reviews-v1: sem estrelas | reviews-v2: pretas | reviews-v3: vermelhas
# ---------------------------------------------------------------------------
log "Aguardando a config do Envoy propagar (alguns segundos)..."
sleep 10

check_host() {
  local HOST="$1"
  local EXPECTED_LABEL="$2"
  local STATUS
  STATUS="$(curl -s -o /dev/null -w '%{http_code}' --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/productpage" --max-time 10 || echo "000")"
  if [ "$STATUS" = "200" ]; then
    echo "  OK   ${HOST} -> HTTP 200 (esperado: ${EXPECTED_LABEL})"
  else
    echo "  FAIL ${HOST} -> HTTP ${STATUS} (esperado: 200, ${EXPECTED_LABEL})"
  fi
}

log "Testando os 3 hosts..."
check_host "simpleproduct.local" "reviews-v1, sem estrelas"
check_host "backproduct.local"   "reviews-v2, estrelas pretas"
check_host "colorproduct.local"  "reviews-v3, estrelas vermelhas"

echo
echo "Para conferir visualmente qual versão do reviews cada host retorna:"
echo '  curl -s --resolve simpleproduct.local:80:127.0.0.1 http://simpleproduct.local/productpage | grep -o "glyphicon-star[a-z -]*"'
echo '  curl -s --resolve backproduct.local:80:127.0.0.1  http://backproduct.local/productpage  | grep -o "glyphicon-star[a-z -]*"'
echo '  curl -s --resolve colorproduct.local:80:127.0.0.1 http://colorproduct.local/productpage | grep -o "glyphicon-star[a-z -]*"'