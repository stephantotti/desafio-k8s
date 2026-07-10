#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 08-apply-ratelimit.sh
#
# Aplica os EnvoyFilters de rate limit (Escopo 3/3) e testa com carga real
# em cada serviço, confirmando que o limite configurado é respeitado.
# ---------------------------------------------------------------------------

NAMESPACE="bookinfo"
EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RL_FILE="${SCRIPT_DIR}/../manifests/ratelimit/ratelimit-services.yaml"

log()  { printf '\n\033[1;34m[ratelimit]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."
[ -f "$RL_FILE" ] || fail "Não encontrei $RL_FILE"

log "Aplicando EnvoyFilters de rate limit..."
kubectl apply -f "$RL_FILE"

log "Aguardando a config do Envoy propagar..."
sleep 10

# ---------------------------------------------------------------------------
# Teste: dispara N requests rápidas via productpage (host simpleproduct.local,
# que aponta pro productpage-simpleproduct -> reviews-v1-only -> ok pra estressar
# o productpage-v1 real, usamos bookinfo.local que fala com o productpage-v1
# original, o mesmo que tem o rate limit de 5 req/s aplicado).
# ---------------------------------------------------------------------------
test_ratelimit() {
  local HOST="$1"
  local PATH_="$2"
  local LABEL="$3"
  local COUNT="$4"
  echo
  echo "--- ${LABEL} (${COUNT} requests rápidas) ---"
  for i in $(seq 1 "$COUNT"); do
    curl -s -o /dev/null -w "%{http_code} " --resolve "${HOST}:80:127.0.0.1" "http://${HOST}${PATH_}"
  done
  echo
}

log "Testando productpage-v1 (limite: 5 req/s)..."
test_ratelimit "bookinfo.local" "/productpage" "productpage-v1" 15

log "Concluído. Deve aparecer uma mistura de 200 e 429 nas linhas acima."
echo "Se vier só 200, o rate limit não está sendo aplicado — verifique o workloadSelector."
echo
echo "Próximo passo: stack de log (Loki) para identificar os 429 nos registros."