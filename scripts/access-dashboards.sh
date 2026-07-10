#!/usr/bin/env bash
set -uo pipefail
# (sem -e aqui de propósito: queremos continuar tentando os outros túneis
# mesmo se um falhar, e reportar o resultado de cada um no final)

# ---------------------------------------------------------------------------
# access-dashboards.sh
#
# Abre (ou reabre) os túneis de port-forward para Grafana, Kiali e
# Prometheus, de forma idempotente e verificada:
#   1. Mata qualquer port-forward antigo para esses serviços (evita o
#      problema de "túnel grudado em pod antigo" após um restart).
#   2. Abre os 3 túneis em background.
#   3. Confirma com curl que cada um responde de verdade antes de reportar
#      sucesso — não confia apenas na mensagem "Forwarding from..." do
#      kubectl, que pode aparecer mesmo com o túnel morto.
#
# Rode este script sempre que: acabou de rodar 06-install-observability.sh,
# reiniciou algum Deployment em 'monitoring', ou os dashboards pararem de
# responder no navegador.
# ---------------------------------------------------------------------------

NAMESPACE="monitoring"
declare -A SERVICES=(
  [grafana]=3000
  [kiali]=20001
  [prometheus]=9090
)

log()  { printf '\n\033[1;34m[access-dashboards]\033[0m %s\n' "$1"; }

command -v kubectl >/dev/null 2>&1 || { echo "ERRO: kubectl não encontrado." >&2; exit 1; }

log "Encerrando port-forwards antigos (se existirem)..."
pkill -9 -f "kubectl port-forward.*-n ${NAMESPACE}" 2>/dev/null || true
sleep 2

FAILED=0

for SVC in "${!SERVICES[@]}"; do
  PORT="${SERVICES[$SVC]}"
  log "Abrindo túnel para ${SVC} (porta ${PORT})..."
  kubectl port-forward -n "$NAMESPACE" "svc/${SVC}" "${PORT}:${PORT}" >/tmp/port-forward-${SVC}.log 2>&1 &
  sleep 2

  STATUS="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${PORT}" || echo "000")"
  if [ "$STATUS" != "000" ]; then
    echo "  OK   ${SVC} -> http://localhost:${PORT} (HTTP ${STATUS})"
  else
    echo "  FAIL ${SVC} -> não respondeu. Log em /tmp/port-forward-${SVC}.log"
    FAILED=1
  fi
done

echo
if [ "$FAILED" -eq 0 ]; then
  echo "Todos os túneis confirmados. URLs:"
  echo "  Grafana:    http://localhost:3000"
  echo "  Kiali:      http://localhost:20001"
  echo "  Prometheus: http://localhost:9090"
else
  echo "Um ou mais túneis falharam — veja os logs indicados acima."
  echo "Causas comuns: pod ainda não está Running (kubectl get pods -n monitoring),"
  echo "ou a porta já está em uso por outro processo não relacionado ao kubectl."
fi

echo
echo "Para encerrar todos os túneis depois: pkill -9 -f \"kubectl port-forward.*-n monitoring\""

exit "$FAILED"