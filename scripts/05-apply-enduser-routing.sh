#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 05-apply-enduser-routing.sh
#
# Aplica o Gateway atualizado (host bookinfo.local), a VirtualService que
# expõe o productpage compartilhado, e a VirtualService de roteamento do
# reviews por header 'end-user' (Ted->v3, Bill->v2, default->v1).
#
# Testa via simulação real de login (POST /login + cookie de sessão), já
# que o productpage só forward o header 'end-user' a partir de sessão
# logada — um 'curl -H "end-user: Ted"' direto NÃO funciona (ver
# docs/arquitetura.md, seção 12).
# ---------------------------------------------------------------------------

NAMESPACE="bookinfo"
EXPECTED_CONTEXT="kind-bookinfo-challenge"
HOST="bookinfo.local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTING_DIR="${SCRIPT_DIR}/../manifests/routing"

log()  { printf '\n\033[1;34m[enduser-routing]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."

for f in "${ROUTING_DIR}/gateway.yaml" \
         "${ROUTING_DIR}/virtualservice-bookinfo-default.yaml" \
         "${ROUTING_DIR}/virtualservice-reviews-enduser.yaml"; do
  [ -f "$f" ] || fail "Não encontrei $f"
done

log "Aplicando Gateway atualizado (host bookinfo.local)..."
kubectl apply -f "${ROUTING_DIR}/gateway.yaml"

log "Aplicando VirtualService do productpage compartilhado..."
kubectl apply -f "${ROUTING_DIR}/virtualservice-bookinfo-default.yaml"

log "Aplicando VirtualService de roteamento do reviews por end-user..."
kubectl apply -f "${ROUTING_DIR}/virtualservice-reviews-enduser.yaml"

log "Aguardando a config do Envoy propagar..."
sleep 10

# ---------------------------------------------------------------------------
# Função de teste: faz login como um usuário, guarda o cookie de sessão,
# acessa /productpage com esse cookie, e reporta a cor das estrelas.
# ---------------------------------------------------------------------------
test_user() {
  local USER="$1"
  local EXPECTED="$2"
  local COOKIEJAR
  COOKIEJAR="$(mktemp)"

  if [ -n "$USER" ]; then
    curl -s -c "$COOKIEJAR" --resolve "${HOST}:80:127.0.0.1" \
      -d "username=${USER}" "http://${HOST}/login" -o /dev/null
  fi

  local BODY
  BODY="$(curl -s -b "$COOKIEJAR" --resolve "${HOST}:80:127.0.0.1" "http://${HOST}/productpage")"
  rm -f "$COOKIEJAR"

  local LABEL="sem login"
  [ -n "$USER" ] && LABEL="end-user: ${USER}"

  if echo "$BODY" | grep -qi 'style="color:\s*red'; then
    echo "  ${LABEL} -> estrelas VERMELHAS (reviews-v3) | esperado: ${EXPECTED}"
  elif echo "$BODY" | grep -qi 'style="color:\s*black'; then
    echo "  ${LABEL} -> estrelas PRETAS (reviews-v2) | esperado: ${EXPECTED}"
  elif echo "$BODY" | grep -q 'glyphicon-star'; then
    echo "  ${LABEL} -> estrelas sem cor identificada pelo padrão de busca | esperado: ${EXPECTED}"
    echo "       (trecho real do HTML, para ajustar o grep se necessário:)"
    echo "$BODY" | grep -o '.\{0,20\}glyphicon-star.\{0,40\}' | head -1 | sed 's/^/       /'
  else
    echo "  ${LABEL} -> SEM estrelas (reviews-v1) | esperado: ${EXPECTED}"
  fi
}

log "Testando roteamento por end-user (login simulado)..."
test_user "Ted"  "vermelhas (v3)"
test_user "Bill" "pretas (v2)"
test_user ""     "sem estrelas (v1, default sem login)"