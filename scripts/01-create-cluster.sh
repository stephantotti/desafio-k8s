#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 01-create-cluster.sh
#
# Cria (de forma idempotente) o cluster Kind usado no desafio, com:
#   - Node image pinada por digest (reprodutibilidade — ver kind-config.yaml)
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
# Criação idempotente do cluster — checa existência ANTES de checar portas.
# Se o cluster já existe, as portas 80/443 estarem "em uso" é ESPERADO (é
# o próprio container do nosso cluster que as ocupa de propósito) — checar
# a porta antes disso gerava falso positivo de conflito depois de qualquer
# reboot/retomada, quando o container já estava rodando de novo sozinho.
# ---------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Cluster '${CLUSTER_NAME}' já existe — pulando criação e checagem de portas."

  # 'kind get clusters' lista pelo nome, mesmo que o container docker esteja
  # parado (ex: depois de reiniciar a máquina) — sem isso, o 'kubectl wait'
  # logo abaixo travaria esperando um node que nunca vai ficar Ready.
  CONTAINER_STATUS="$(docker inspect -f '{{.State.Status}}' "${CLUSTER_NAME}-control-plane" 2>/dev/null || echo "ausente")"
  if [ "$CONTAINER_STATUS" != "running" ] && [ "$CONTAINER_STATUS" != "ausente" ]; then
    log "Container do cluster estava '${CONTAINER_STATUS}' — iniciando..."
    docker start "${CLUSTER_NAME}-control-plane" >/dev/null
  fi
else
  log "Cluster não existe ainda — checando se as portas 80/443 estão livres..."
  for PORT in 80 443; do
    if ss -ltn "( sport = :$PORT )" 2>/dev/null | grep -q ":$PORT"; then
      fail "Porta $PORT já está em uso no host. Libere-a (ex: pare Apache/Nginx locais) antes de continuar."
    fi
  done

  log "Criando cluster '${CLUSTER_NAME}'..."
  kind create cluster --config "$KIND_CONFIG"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

log "Aguardando o node ficar Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s

log "Cluster pronto:"
kubectl get nodes -o wide
kubectl cluster-info --context "kind-${CLUSTER_NAME}"