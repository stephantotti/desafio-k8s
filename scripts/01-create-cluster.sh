#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 01-create-cluster.sh
#
# Cria o cluster Kind, com:
#   - Node image pinada por digest 
#   - extraPortMappings 80/443 → 30080/30443 (substitui o LoadBalancer que
#     o kind não tem nativamente; o istio-ingressgateway será exposto como
#     NodePort nessas mesmas portas no script 02-install-istio.sh)
# ---------------------------------------------------------------------------

CLUSTER_NAME="bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CONFIG="${SCRIPT_DIR}/../kind-config.yaml"

log()  { printf '\n\033[1;34m[create-cluster]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kind    >/dev/null 2>&1 || fail "kind não encontrado. Rode antes: scripts/00-install-tools.sh"
command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado. Rode antes: scripts/00-install-tools.sh"
[ -f "$KIND_CONFIG" ] || fail "Não encontrei $KIND_CONFIG"

if ! docker info >/dev/null 2>&1; then
  fail "Docker não está respondendo. Rode 'sudo systemctl status docker' e/ou 'newgrp docker'."
fi

# ---------------------------------------------------------------------------
# Checagem de portas antes de criar (80/443 precisam estar livres no host)
# ---------------------------------------------------------------------------
for PORT in 80 443; do
  if ss -ltn "( sport = :$PORT )" 2>/dev/null | grep -q ":$PORT"; then
    fail "Porta $PORT já está em uso no host. Libere-a (ex: pare Apache/Nginx locais) antes de continuar."
  fi
done

# ---------------------------------------------------------------------------
# Criação idempotente do cluster
# ---------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Cluster '${CLUSTER_NAME}' já existe — pulando criação."
else
  log "Criando cluster '${CLUSTER_NAME}'..."
  kind create cluster --config "$KIND_CONFIG"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

log "Aguardando o node ficar Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s

log "Cluster pronto:"
kubectl get nodes -o wide
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo
echo "Próximo passo: scripts/02-install-istio.sh"