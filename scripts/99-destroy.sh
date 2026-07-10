#!/usr/bin/env bash
set -uo pipefail

# ---------------------------------------------------------------------------
# 99-destroy.sh
#
# Remove o cluster Kind por completo (todos os namespaces, workloads,
# volumes efêmeros — tudo junto, já que é tudo dentro do mesmo container
# Docker do node). Mata também qualquer port-forward pendente antes.
# ---------------------------------------------------------------------------

CLUSTER_NAME="bookinfo-challenge"

log() { printf '\n\033[1;34m[destroy]\033[0m %s\n' "$1"; }

command -v kind >/dev/null 2>&1 || { echo "kind não encontrado, nada a fazer." >&2; exit 0; }

log "Encerrando port-forwards ativos..."
pkill -9 -f "kubectl port-forward.*-n monitoring" 2>/dev/null || true

log "Destruindo cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "$CLUSTER_NAME"

log "Concluído. Para recriar do zero: make bootstrap"