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

for f in prometheus.yaml grafana.yaml kiali.yaml custom-dashboard-configmap.yaml; do
  [ -f "${OBS_DIR}/${f}" ] || fail "Não encontrei ${OBS_DIR}/${f}"
done

log "Aplicando ConfigMap do dashboard customizado (antes do Grafana, que já monta essa pasta)..."
kubectl apply -f "${OBS_DIR}/custom-dashboard-configmap.yaml"

log "Aplicando Prometheus..."
kubectl apply -f "${OBS_DIR}/prometheus.yaml"

log "Aplicando Grafana..."
kubectl apply -f "${OBS_DIR}/grafana.yaml"

log "Aplicando Kiali..."
kubectl apply -f "${OBS_DIR}/kiali.yaml"

log "Aguardando os deployments ficarem prontos (1a rodada)..."
kubectl -n monitoring rollout status deployment/prometheus --timeout=180s
kubectl -n monitoring rollout status deployment/grafana --timeout=180s
kubectl -n monitoring rollout status deployment/kiali --timeout=180s

# ---------------------------------------------------------------------------
# Restart explícito do Grafana SEMPRE: o Kubernetes não reinicia pods
# automaticamente quando só o CONTEÚDO de um ConfigMap muda (só quando a
# spec do Deployment muda) — como o dashboard customizado é montado via
# ConfigMap, um "kubectl apply" sozinho pode não bastar para o Grafana
# enxergar dashboards atualizados. Reiniciar sempre é barato e idempotente,
# evita depender de lembrar disso manualmente (ver docs/arquitetura.md).
# ---------------------------------------------------------------------------
log "Reiniciando Grafana para garantir que o dashboard customizado seja carregado..."
kubectl -n monitoring rollout restart deployment/grafana
kubectl -n monitoring rollout status deployment/grafana --timeout=120s

log "Concluído. Pods em monitoring:"
kubectl get pods -n monitoring

echo
log "Abrindo os dashboards automaticamente..."
if ! "${SCRIPT_DIR}/access-dashboards.sh"; then
  echo
  echo "AVISO: a stack de observabilidade subiu OK, mas algum túnel de acesso"
  echo "falhou (pode ser hiccup momentâneo de rede). Rode manualmente depois:"
  echo "  scripts/access-dashboards.sh"
fi
echo
echo "Próximo passo: gerar tráfego nos 3 hosts + end-user para popular os"
echo "dashboards, e importar/conferir os painéis de Ingress Gateway e por Service."