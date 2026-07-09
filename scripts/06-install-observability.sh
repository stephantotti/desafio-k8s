#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 06-install-observability.sh
#
# Aplica Prometheus + Grafana + Kiali no namespace 'monitoring' (versão
# 1.30 dos addons oficiais do Istio, ajustada — ver docs/arquitetura.md).
# ---------------------------------------------------------------------------

EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBS_DIR="${SCRIPT_DIR}/../manifests/observability"

log()  { printf '\n\033[1;34m[observability]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[ "$CURRENT_CONTEXT" = "$EXPECTED_CONTEXT" ] || fail "Contexto atual é '${CURRENT_CONTEXT}', esperado '${EXPECTED_CONTEXT}'."

for f in prometheus.yaml grafana.yaml kiali.yaml; do
  [ -f "${OBS_DIR}/${f}" ] || fail "Não encontrei ${OBS_DIR}/${f}"
done

log "Aplicando Prometheus..."
kubectl apply -f "${OBS_DIR}/prometheus.yaml"

log "Aplicando Grafana..."
kubectl apply -f "${OBS_DIR}/grafana.yaml"

log "Aplicando Kiali..."
kubectl apply -f "${OBS_DIR}/kiali.yaml"

log "Aguardando os deployments ficarem prontos..."
kubectl -n monitoring rollout status deployment/prometheus --timeout=180s
kubectl -n monitoring rollout status deployment/grafana --timeout=180s
kubectl -n monitoring rollout status deployment/kiali --timeout=180s

log "Concluído. Pods em monitoring:"
kubectl get pods -n monitoring

echo
echo "Para acessar os dashboards (rode cada um em um terminal separado):"
echo "  kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "  kubectl port-forward -n monitoring svc/kiali 20001:20001"
echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo
echo "Depois, no navegador:"
echo "  Grafana:    http://localhost:3000"
echo "  Kiali:      http://localhost:20001"
echo "  Prometheus: http://localhost:9090"