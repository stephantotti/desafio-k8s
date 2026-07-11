#!/usr/bin/env bash
set -uo pipefail
# (sem -e: queremos rodar TODOS os testes de regressão mesmo se um falhar,
# e reportar o resultado completo no final, não parar no primeiro erro)

# ---------------------------------------------------------------------------
# 10-apply-mtls.sh
#
# Aplica mTLS STRICT no namespace bookinfo e re-testa os 3 escopos do
# desafio, para confirmar que nada quebrou (mTLS deveria ser transparente
# para a aplicação, mas isso precisa ser validado na prática, não assumido).
# ---------------------------------------------------------------------------

NAMESPACE="bookinfo"
EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTLS_FILE="${SCRIPT_DIR}/../manifests/security/peer-authentication.yaml"

log()  { printf '\n\033[1;34m[mtls]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."
[ -f "$MTLS_FILE" ] || fail "Não encontrei $MTLS_FILE"

log "Aplicando PeerAuthentication STRICT no namespace '${NAMESPACE}'..."
kubectl apply -f "$MTLS_FILE"

log "Aguardando a config propagar nos sidecars..."
sleep 25

FAILED=0
check() {
  local LABEL="$1"
  local EXPECTED="$2"
  local ACTUAL="$3"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "  OK   ${LABEL}"
  else
    echo "  FAIL ${LABEL} (esperado: ${EXPECTED}, veio: ${ACTUAL})"
    FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Regressão Escopo 1/3 — roteamento por host
# ---------------------------------------------------------------------------
log "Regressão Escopo 1/3 (roteamento por host)..."
for HOST in simpleproduct.local backproduct.local colorproduct.local; do
  STATUS="$(curl -s -o /dev/null -w '%{http_code}' --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/productpage" --max-time 10)"
  check "${HOST} -> HTTP 200" "200" "$STATUS"
done

# ---------------------------------------------------------------------------
# Regressão Escopo 2/3 — roteamento por end-user (com retry — a config do
# mTLS pode levar alguns segundos a mais para propagar em todos os sidecars)
# ---------------------------------------------------------------------------
log "Regressão Escopo 2/3 (roteamento por end-user)..."
COLOR=""
for ATTEMPT in 1 2 3; do
  COOKIE="$(mktemp)"
  curl -s -c "$COOKIE" --resolve bookinfo.local:80:127.0.0.1 -d "username=Ted" http://bookinfo.local/login -o /dev/null
  COLOR="$(curl -s -b "$COOKIE" --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/api/v1/products/0/reviews | grep -o '"color": "[a-z]*"' | head -1)"
  rm -f "$COOKIE"
  [ "$COLOR" = '"color": "red"' ] && break
  echo "  (tentativa ${ATTEMPT}/3 sem sucesso, aguardando mais um pouco...)"
  sleep 10
done
check "login Ted -> reviews-v3 (red)" '"color": "red"' "$COLOR"

# ---------------------------------------------------------------------------
# Regressão Escopo 3/3 — rate limiting ainda ativo
# ---------------------------------------------------------------------------
log "Regressão Escopo 3/3 (rate limiting)..."
RESULTS="$(for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/productpage; done)"
echo "  Resultado bruto: ${RESULTS}"
if echo "$RESULTS" | grep -q "429"; then
  echo "  OK   rate limit ainda bloqueando (429 presente)"
else
  echo "  FAIL nenhum 429 encontrado — rate limit pode ter parado de funcionar"
  FAILED=1
fi

echo
if [ "$FAILED" -eq 0 ]; then
  log "mTLS STRICT aplicado com sucesso — todos os escopos continuam funcionando."
else
  log "ATENÇÃO: algo quebrou com mTLS STRICT. Considere reverter:"
  echo "  kubectl delete peerauthentication default -n ${NAMESPACE}"
fi

exit "$FAILED"