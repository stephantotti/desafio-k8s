#!/usr/bin/env bash
set -uo pipefail

# ---------------------------------------------------------------------------
# resume-cluster.sh
#
# Retoma o ambiente depois que a máquina foi desligada/reiniciada. Os
# containers do Kind (Docker) e os pods do cluster sobrevivem a um reboot
# (o Docker Desktop/daemon costuma resubir os containers automaticamente,
# ou precisam de um 'docker start' manual) — o que NÃO sobrevive é a sessão
# de terminal com os 'port-forward' abertos, que morre junto com o reboot.
#
# Este script cobre os dois cenários: garante que o container do node do
# Kind está de pé, confirma que o cluster responde, e reabre os túneis.
# Idempotente — seguro rodar mesmo se nada tiver caído.
# ---------------------------------------------------------------------------

CLUSTER_CONTAINER="bookinfo-challenge-control-plane"
EXPECTED_CONTEXT="kind-bookinfo-challenge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;34m[resume-cluster]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v docker  >/dev/null 2>&1 || fail "docker não encontrado."
command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."

if ! docker info >/dev/null 2>&1; then
  fail "Docker não está respondendo. No WSL2, pode precisar rodar: sudo service docker start"
fi

CONTAINER_STATUS="$(docker inspect -f '{{.State.Status}}' "$CLUSTER_CONTAINER" 2>/dev/null || echo "ausente")"
case "$CONTAINER_STATUS" in
  running)
    log "Container do cluster já está rodando."
    ;;
  ausente)
    fail "Container '${CLUSTER_CONTAINER}' não existe. Rode scripts/01-create-cluster.sh primeiro."
    ;;
  *)
    log "Container do cluster estava '${CONTAINER_STATUS}' — iniciando..."
    docker start "$CLUSTER_CONTAINER" >/dev/null
    ;;
esac

log "Aguardando o node ficar Ready..."
kubectl config use-context "$EXPECTED_CONTEXT" >/dev/null 2>&1
if ! kubectl wait --for=condition=Ready node --all --timeout=120s 2>/dev/null; then
  fail "Node não ficou Ready a tempo. Verifique 'kubectl get nodes' e 'docker logs ${CLUSTER_CONTAINER}'."
fi

log "Verificando pods em todos os namespaces do projeto..."
for NS in bookinfo istio-system monitoring logging; do
  NOT_READY="$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -v -E 'Running|Completed' || true)"
  if [ -n "$NOT_READY" ]; then
    echo "  AVISO em '${NS}':"
    echo "$NOT_READY" | sed 's/^/    /'
  else
    echo "  OK   ${NS}: todos os pods Running"
  fi
done

log "Reabrindo túneis de acesso..."
"${SCRIPT_DIR}/access-dashboards.sh" || true

echo
echo "Se algum namespace mostrou AVISO acima, dê mais alguns segundos e rode:"
echo "  kubectl get pods -n <namespace>"
echo "Pods que não estabilizarem sozinhos podem precisar de: kubectl delete pod <nome> -n <namespace>"