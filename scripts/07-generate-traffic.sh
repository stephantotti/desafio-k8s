#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 07-generate-traffic.sh
#
# Gera tráfego real nos 3 hosts (Escopo 1/3) e simula os 3 usuários do
# end-user (Escopo 2/3) em loop, para popular os dashboards do Grafana/Kiali.
# Roda por DURATION segundos (default 60) e para sozinho.
# ---------------------------------------------------------------------------

DURATION="${1:-60}"
END=$((SECONDS + DURATION))

echo "Gerando tráfego por ${DURATION}s (Ctrl+C para parar antes)..."

COOKIE_TED="$(mktemp)"
COOKIE_BILL="$(mktemp)"
curl -s -c "$COOKIE_TED"  --resolve bookinfo.local:80:127.0.0.1 -d "username=Ted"  http://bookinfo.local/login -o /dev/null
curl -s -c "$COOKIE_BILL" --resolve bookinfo.local:80:127.0.0.1 -d "username=Bill" http://bookinfo.local/login -o /dev/null

while [ "$SECONDS" -lt "$END" ]; do
  curl -s -o /dev/null --resolve simpleproduct.local:80:127.0.0.1 http://simpleproduct.local/productpage
  curl -s -o /dev/null --resolve backproduct.local:80:127.0.0.1  http://backproduct.local/productpage
  curl -s -o /dev/null --resolve colorproduct.local:80:127.0.0.1 http://colorproduct.local/productpage
  curl -s -o /dev/null -b "$COOKIE_TED"  --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/productpage
  curl -s -o /dev/null -b "$COOKIE_BILL" --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/productpage
  curl -s -o /dev/null --resolve bookinfo.local:80:127.0.0.1 http://bookinfo.local/productpage
  sleep 0.3
done

rm -f "$COOKIE_TED" "$COOKIE_BILL"
echo "Concluído. Confira os dashboards no Grafana (Istio Mesh / Service Dashboard)."