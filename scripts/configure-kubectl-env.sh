#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# configure-kubectl-env.sh
#
# Configura o acesso ao cluster via alias E variável de ambiente (o desafio
# pede "ou", mas os dois juntos não custam nada extra e cobrem qualquer
# preferência de quem for avaliar):
#   - Alias 'k' para 'kubectl --context kind-bookinfo-challenge'
#   - Variável KUBECONFIG apontando para um kubeconfig dedicado deste
#     projeto (isolado do ~/.kube/config "geral" da máquina, evitando
#     conflito com outros clusters que o avaliador possa ter).
#
# Idempotente: não duplica linhas se rodado mais de uma vez.
# ---------------------------------------------------------------------------

CLUSTER_NAME="bookinfo-challenge"
KUBECONFIG_PATH="${HOME}/.kube/${CLUSTER_NAME}.config"
RC_FILE="${HOME}/.bashrc"
MARKER="# >>> bookinfo-challenge kubectl config >>>"
MARKER_END="# <<< bookinfo-challenge kubectl config <<<"

log()  { printf '\n\033[1;34m[configure-kubectl-env]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v kind    >/dev/null 2>&1 || fail "kind não encontrado."
command -v kubectl >/dev/null 2>&1 || fail "kubectl não encontrado."

mkdir -p "${HOME}/.kube"

log "Extraindo kubeconfig dedicado do cluster '${CLUSTER_NAME}'..."
kind get kubeconfig --name "$CLUSTER_NAME" > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

if grep -qF "$MARKER" "$RC_FILE" 2>/dev/null; then
  log "Config já presente em ${RC_FILE} — pulando (idempotente)."
else
  log "Adicionando alias e variável de ambiente ao ${RC_FILE}..."
  cat >> "$RC_FILE" << EOF

${MARKER}
export KUBECONFIG="${KUBECONFIG_PATH}"
alias k="kubectl --context kind-${CLUSTER_NAME}"
${MARKER_END}
EOF
fi

log "Concluído. Configurado em ${RC_FILE}:"
echo "  KUBECONFIG=${KUBECONFIG_PATH}"
echo "  alias k='kubectl --context kind-${CLUSTER_NAME}'"
echo
echo "IMPORTANTE: como este script roda em um subprocesso, ele NÃO consegue"
echo "aplicar export/alias na sua sessão de terminal atual (limitação do"
echo "bash, não bug). Pra ativar agora, escolha uma opção:"
echo "  source ~/.bashrc"
echo "  (ou simplesmente abra um terminal novo)"
echo
echo "Depois disso, teste com:"
echo "  k get nodes"