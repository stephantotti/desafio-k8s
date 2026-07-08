#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 00-install-tools.sh
#
# Instala as ferramentas do desafio em versões FIXAS e VALIDADAS.
# Diferente de uma checagem simples de "já existe o binário?", este script
# verifica se a versão instalada é EXATAMENTE a esperada — se o avaliador já
# tiver uma versão diferente (mais nova ou mais velha) instalada, o script
# substitui por esta, garantindo reprodutibilidade.
#
# Instala em /usr/local/bin (requer sudo) para evitar problemas de PATH:
# ---------------------------------------------------------------------------

# --- Versões fixas, validadas em ambiente de desenvolvimento -----------------
KUBECTL_VERSION="v1.36.2"   # compatível com kind (node k8s 1.35) e istio 1.30
KIND_VERSION="v0.31.0"      # node image default: kindest/node:v1.35.0
ISTIO_VERSION="1.30.2"      # suportada oficialmente para k8s 1.32-1.36
HELM_VERSION="v3.15.3"      # helm 3 estável; se preferir v4 já instalado, ver nota no fim

INSTALL_DIR="/usr/local/bin"

log()  { printf '\n\033[1;34m[install-tools]\033[0m %s\n' "$1"; }
fail() { echo "ERRO: $1" >&2; exit 1; }

command -v curl  >/dev/null 2>&1 || fail "curl não encontrado. Instale com: sudo apt-get install -y curl"
command -v tar   >/dev/null 2>&1 || fail "tar não encontrado. Instale com: sudo apt-get install -y tar"
command -v sudo  >/dev/null 2>&1 || fail "sudo não encontrado. Rode este script como root ou instale sudo."

case "$(uname -m)" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) fail "Arquitetura não suportada: $(uname -m)" ;;
esac
log "Linux/${ARCH} detectado. Instalando em ${INSTALL_DIR} (versões fixas)."

# ---------------------------------------------------------------------------
# kubectl
# ---------------------------------------------------------------------------
CURRENT_KUBECTL="$(command -v kubectl >/dev/null 2>&1 && kubectl version --client 2>/dev/null | grep -oP 'GitVersion:"\K[^"]+' || echo "ausente")"
if [ "$CURRENT_KUBECTL" = "$KUBECTL_VERSION" ]; then
  log "kubectl já está na versão esperada (${KUBECTL_VERSION}) — pulando."
else
  log "kubectl atual: ${CURRENT_KUBECTL} | esperado: ${KUBECTL_VERSION} → reinstalando..."
  curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl "${INSTALL_DIR}/kubectl"
  log "kubectl ${KUBECTL_VERSION} instalado em ${INSTALL_DIR}/kubectl"
fi

# ---------------------------------------------------------------------------
# kind
# ---------------------------------------------------------------------------
CURRENT_KIND="$(command -v kind >/dev/null 2>&1 && kind version | awk '{print $2}' || echo "ausente")"
if [ "$CURRENT_KIND" = "$KIND_VERSION" ]; then
  log "kind já está na versão esperada (${KIND_VERSION}) — pulando."
else
  log "kind atual: ${CURRENT_KIND} | esperado: ${KIND_VERSION} → reinstalando..."
  curl -sLo /tmp/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}"
  chmod +x /tmp/kind
  sudo mv /tmp/kind "${INSTALL_DIR}/kind"
  log "kind ${KIND_VERSION} instalado em ${INSTALL_DIR}/kind"
fi

# ---------------------------------------------------------------------------
# istioctl
# ---------------------------------------------------------------------------
CURRENT_ISTIO="$(command -v istioctl >/dev/null 2>&1 && istioctl version --remote=false 2>/dev/null | grep -oP 'client version: \K.+' || echo "ausente")"
if [ "$CURRENT_ISTIO" = "$ISTIO_VERSION" ]; then
  log "istioctl já está na versão esperada (${ISTIO_VERSION}) — pulando."
else
  log "istioctl atual: ${CURRENT_ISTIO} | esperado: ${ISTIO_VERSION} → reinstalando..."
  TMP_DIR="$(mktemp -d)"
  curl -sLo "$TMP_DIR/istio.tar.gz" \
    "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-${ARCH}.tar.gz"
  tar -xzf "$TMP_DIR/istio.tar.gz" -C "$TMP_DIR"
  FOUND_BIN="$(find "$TMP_DIR" -type f -name istioctl | head -n1)"
  [ -n "$FOUND_BIN" ] || fail "istioctl não encontrado no pacote baixado."
  sudo cp "$FOUND_BIN" "${INSTALL_DIR}/istioctl"
  sudo chmod +x "${INSTALL_DIR}/istioctl"
  rm -rf "$TMP_DIR"
  log "istioctl ${ISTIO_VERSION} instalado em ${INSTALL_DIR}/istioctl"
fi

# ---------------------------------------------------------------------------
# helm
# ---------------------------------------------------------------------------
CURRENT_HELM="$(command -v helm >/dev/null 2>&1 && helm version --short 2>/dev/null | grep -oP '^\K[^+]+' || echo "ausente")"
if [ "$CURRENT_HELM" = "$HELM_VERSION" ]; then
  log "helm já está na versão esperada (${HELM_VERSION}) — pulando."
else
  log "helm atual: ${CURRENT_HELM} | esperado: ${HELM_VERSION} → reinstalando..."
  TMP_DIR="$(mktemp -d)"
  curl -sLo "$TMP_DIR/helm.tar.gz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
  tar -xzf "$TMP_DIR/helm.tar.gz" -C "$TMP_DIR"
  sudo cp "$TMP_DIR/linux-${ARCH}/helm" "${INSTALL_DIR}/helm"
  sudo chmod +x "${INSTALL_DIR}/helm"
  rm -rf "$TMP_DIR"
  log "helm ${HELM_VERSION} instalado em ${INSTALL_DIR}/helm"
fi

# ---------------------------------------------------------------------------
# Docker — instala automaticamente se ausente; valida se o daemon está de pé
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "docker não encontrado. Instalando via script oficial (get.docker.com)..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  log "docker instalado. Adicionado o usuário '$USER' ao grupo 'docker'."
  echo
  echo "IMPORTANTE: a permissão de grupo só vale numa sessão nova."
  echo "Rode 'newgrp docker' agora, ou abra um novo terminal, antes de continuar."
fi

if ! sudo systemctl is-active --quiet docker 2>/dev/null && ! docker info >/dev/null 2>&1; then
  log "Serviço docker não está ativo. Tentando iniciar..."
  sudo systemctl enable --now docker 2>/dev/null || sudo service docker start
fi

if docker info >/dev/null 2>&1; then
  log "Docker OK e respondendo ($(docker --version))."
else
  echo
  echo "AVISO: docker instalado mas ainda não responde (docker info falhou)."
  echo "Verifique com: sudo systemctl status docker"
  echo "Se for erro de permissão, rode: newgrp docker  (ou abra um terminal novo)"
fi

log "Concluído. Versões ativas:"
kubectl version --client 2>/dev/null | head -1
kind version
istioctl version --remote=false 2>/dev/null
helm version --short 2>/dev/null

echo
echo "NOTA: se algum 'command -v' acima ainda mostrar uma versão diferente da"
echo "fixada, rode: which -a <ferramenta>  — outro binário no PATH está na frente"
echo "de ${INSTALL_DIR}. Nesse caso, sudo rm o binário concorrente encontrado."