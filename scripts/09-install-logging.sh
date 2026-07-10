#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 09-install-logging.sh
#
# Instala Loki + Promtail (Helm, namespace 'logging' — ver docs/arquitetura.md
# seção 8) e reinicia o Grafana para carregar o datasource Loki, cuja URL já
# vem pré-configurada no addon mas precisou ser corrigida para apontar para
# o namespace 'logging' (ver comentário no grafana.yaml).
# ---------------------------------------------------------------------------

EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;34m[logging]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."
command -v helm    >/dev/null 2>&1 || fail "helm não encontrado."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."

log "Adicionando/atualizando o repo Helm do Grafana..."
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

log "Instalando/atualizando Loki + Promtail (namespace logging)..."
helm upgrade --install loki grafana/loki-stack \
  --namespace logging \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=false \
  --wait --timeout 5m

log "Aplicando correção da URL do datasource Loki no Grafana..."
kubectl apply -f "${SCRIPT_DIR}/../manifests/observability/grafana.yaml"

log "Reiniciando Grafana para carregar o datasource Loki..."
kubectl -n monitoring rollout restart deployment/grafana
kubectl -n monitoring rollout status deployment/grafana --timeout=120s

log "Concluído. Pods em logging:"
kubectl get pods -n logging

echo
log "Reabrindo túneis de acesso..."
"${SCRIPT_DIR}/access-dashboards.sh" || true

echo
echo
log "Verificando o formato real do log diretamente no pod (antes de confiar na query do Loki)..."
kubectl logs -n bookinfo deployment/productpage-v1 -c istio-proxy --tail=200 2>/dev/null | grep " 429 " | head -3 || echo "  (nenhum 429 recente nesse pod — rode scripts/08-apply-ratelimit.sh de novo para gerar mais tráfego)"

echo
echo "No Grafana, vá em Explore, selecione o datasource 'Loki' e teste a query:"
echo '  {namespace="bookinfo"} |= "local_rate_limited"'
echo
echo "O log padrão do Envoy é texto posicional (não JSON). 'local_rate_limited'"
echo "é o response flag específico que o Envoy grava quando é o rate limit"
echo "local que bloqueou a requisição (mais preciso que buscar só \"429\","
echo "que poderia bater com outras causas). Confira acima se esse padrão"
echo "bateu com o formato real do log do seu pod antes de considerar validado."